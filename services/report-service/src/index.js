// Express server for report-service microservice - MySQL version (No SNS)

const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");

const app = express();
const PORT = process.env.PORT || 3002;

// MySQL connection pool - can use read replica for GET requests
const writePool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || "admin",
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "inspection_platform",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Read replica pool (falls back to primary if not configured)
const readPool = mysql.createPool({
  host: process.env.DB_READ_HOST || process.env.DB_HOST || "localhost",
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || "admin",
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "inspection_platform",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Middleware
app.use(cors());
app.use(express.json());

app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
  next();
});

// Health check
app.get("/health", async (req, res) => {
  try {
    await writePool.query("SELECT 1");
    res.json({
      status: "healthy",
      service: "report-service",
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({ status: "unhealthy", error: error.message });
  }
});

// Helper function to calculate overall condition
function calculateOverallCondition(checklist) {
  const scores = { Good: 3, Fair: 2, Poor: 1 };
  const values = Object.values(checklist).filter((v) => v !== null);
  if (values.length === 0) return null;
  const total = values.reduce((sum, v) => sum + (scores[v] || 0), 0);
  const avg = total / values.length;
  if (avg >= 2.5) return "Good";
  if (avg >= 1.5) return "Fair";
  return "Poor";
}

// ==================== REPORT ROUTES ====================

// Generate report for an inspection
app.post("/api/reports/:inspectionId", async (req, res) => {
  try {
    const { inspectionId } = req.params;

    // Fetch inspection data
    const [rows] = await writePool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: "Inspection not found" });
    }

    const inspection = rows[0];

    // Validate checklist is complete
    const checklistFields = [
      "checklist_roof",
      "checklist_foundation",
      "checklist_plumbing",
      "checklist_electrical",
      "checklist_hvac",
    ];
    const incompleteFields = checklistFields.filter(
      (f) => inspection[f] === null,
    );

    if (incompleteFields.length > 0) {
      return res.status(400).json({
        error: "Inspection checklist is incomplete",
        missingFields: incompleteFields.map((f) => f.replace("checklist_", "")),
      });
    }

    // Get images
    const [images] = await writePool.query(
      "SELECT image_id, s3_key, file_name FROM inspection_images WHERE inspection_id = ?",
      [inspectionId],
    );

    const now = new Date();

    // Update inspection status to REPORT_GENERATED
    await writePool.query(
      `UPDATE inspections SET status = 'REPORT_GENERATED', report_generated_at = ? WHERE inspection_id = ?`,
      [now, inspectionId],
    );

    const checklist = {
      roof: inspection.checklist_roof,
      foundation: inspection.checklist_foundation,
      plumbing: inspection.checklist_plumbing,
      electrical: inspection.checklist_electrical,
      hvac: inspection.checklist_hvac,
    };

    // Generate report object
    const report = {
      reportId: `report_${inspectionId}`,
      inspectionId,
      generatedAt: now.toISOString(),
      propertyAddress: inspection.property_address,
      inspector: {
        name: inspection.inspector_name,
        email: inspection.inspector_email,
      },
      client: {
        name: inspection.client_name,
        email: inspection.client_email,
      },
      summary: {
        checklist,
        overallCondition: calculateOverallCondition(checklist),
        notes: inspection.notes,
        totalImages: images.length,
      },
      images: images.map((img) => ({
        imageId: img.image_id,
        s3Key: img.s3_key,
        fileName: img.file_name,
      })),
    };

    console.log(`Report generated for inspection ${inspectionId}`);

    res.json({ message: "Report generated successfully", report });
  } catch (error) {
    console.error("Generate report error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// Get report for an inspection (uses read replica)
app.get("/api/reports/:inspectionId", async (req, res) => {
  try {
    const { inspectionId } = req.params;

    // Use read replica for GET requests
    const [rows] = await readPool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: "Inspection not found" });
    }

    const inspection = rows[0];

    if (inspection.status !== "REPORT_GENERATED") {
      return res
        .status(400)
        .json({ error: "Report has not been generated for this inspection" });
    }

    // Get images from read replica
    const [images] = await readPool.query(
      "SELECT image_id, s3_key, file_name FROM inspection_images WHERE inspection_id = ?",
      [inspectionId],
    );

    const checklist = {
      roof: inspection.checklist_roof,
      foundation: inspection.checklist_foundation,
      plumbing: inspection.checklist_plumbing,
      electrical: inspection.checklist_electrical,
      hvac: inspection.checklist_hvac,
    };

    // Reconstruct report from inspection data
    const report = {
      reportId: `report_${inspectionId}`,
      inspectionId,
      generatedAt: inspection.report_generated_at?.toISOString(),
      propertyAddress: inspection.property_address,
      inspector: {
        name: inspection.inspector_name,
        email: inspection.inspector_email,
      },
      client: {
        name: inspection.client_name,
        email: inspection.client_email,
      },
      summary: {
        checklist,
        overallCondition: calculateOverallCondition(checklist),
        notes: inspection.notes,
        totalImages: images.length,
      },
      images: images.map((img) => ({
        imageId: img.image_id,
        s3Key: img.s3_key,
        fileName: img.file_name,
      })),
    };

    res.json({ report });
  } catch (error) {
    console.error("Get report error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// Error handling
app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res
    .status(500)
    .json({ error: "Internal server error", details: err.message });
});

app.use((req, res) => {
  res.status(404).json({ error: "Not found", path: req.path });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Report Service running on port ${PORT}`);
  console.log(`Database Host (Write): ${process.env.DB_HOST || "localhost"}`);
  console.log(
    `Database Host (Read): ${process.env.DB_READ_HOST || process.env.DB_HOST || "localhost"}`,
  );
});

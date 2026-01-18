// Express server for inspection-api microservice with MySQL and S3 integration

const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { randomUUID } = require("crypto");

const app = express();
const PORT = process.env.PORT || 3001;

// MySQL connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || "admin",
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || "inspection_platform",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0,
});

// S3 client
const s3Client = new S3Client({});
const IMAGE_BUCKET =
  process.env.IMAGE_BUCKET_NAME || "inspection-images-bucket";

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
    await pool.query("SELECT 1");
    res.json({
      status: "healthy",
      service: "inspection-api",
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({ status: "unhealthy", error: error.message });
  }
});

// ==================== INSPECTIONS ROUTES ====================

// Create inspection
app.post("/api/inspections", async (req, res) => {
  try {
    const {
      propertyAddress,
      inspectorName,
      inspectorEmail,
      clientName,
      clientEmail,
    } = req.body;

    if (!propertyAddress || !inspectorName || !inspectorEmail) {
      return res.status(400).json({
        error:
          "Missing required fields: propertyAddress, inspectorName, inspectorEmail",
      });
    }

    const inspectionId = `insp_${randomUUID().slice(0, 8)}`;

    await pool.query(
      `INSERT INTO inspections (inspection_id, property_address, inspector_name, inspector_email, client_name, client_email)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        inspectionId,
        propertyAddress,
        inspectorName,
        inspectorEmail,
        clientName || "",
        clientEmail || "",
      ],
    );

    const [rows] = await pool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );

    res.status(201).json({
      message: "Inspection created successfully",
      inspection: formatInspection(rows[0]),
    });
  } catch (error) {
    console.error("Create inspection error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// List inspections
app.get("/api/inspections", async (req, res) => {
  try {
    const { status } = req.query;
    let query = "SELECT * FROM inspections";
    let params = [];

    if (status) {
      query += " WHERE status = ?";
      params.push(status.toUpperCase());
    }
    query += " ORDER BY created_at DESC";

    const [rows] = await pool.query(query, params);

    // Get images for each inspection
    const inspections = await Promise.all(
      rows.map(async (row) => {
        const [images] = await pool.query(
          "SELECT image_id, s3_key, file_name FROM inspection_images WHERE inspection_id = ?",
          [row.inspection_id],
        );
        return formatInspection(row, images);
      }),
    );

    res.json({ count: inspections.length, inspections });
  } catch (error) {
    console.error("List inspections error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// Get single inspection
app.get("/api/inspections/:inspectionId", async (req, res) => {
  try {
    const { inspectionId } = req.params;

    const [rows] = await pool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: "Inspection not found" });
    }

    const [images] = await pool.query(
      "SELECT image_id, s3_key, file_name FROM inspection_images WHERE inspection_id = ?",
      [inspectionId],
    );

    res.json({ inspection: formatInspection(rows[0], images) });
  } catch (error) {
    console.error("Get inspection error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// Update inspection
app.put("/api/inspections/:inspectionId", async (req, res) => {
  try {
    const { inspectionId } = req.params;
    const { checklist, notes, images, clientName, clientEmail, status } =
      req.body;

    // Check existence
    const [existing] = await pool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );
    if (existing.length === 0) {
      return res.status(404).json({ error: "Inspection not found" });
    }

    // Build dynamic update query
    const updates = [];
    const params = [];

    if (checklist) {
      if (checklist.roof) {
        updates.push("checklist_roof = ?");
        params.push(checklist.roof);
      }
      if (checklist.foundation) {
        updates.push("checklist_foundation = ?");
        params.push(checklist.foundation);
      }
      if (checklist.plumbing) {
        updates.push("checklist_plumbing = ?");
        params.push(checklist.plumbing);
      }
      if (checklist.electrical) {
        updates.push("checklist_electrical = ?");
        params.push(checklist.electrical);
      }
      if (checklist.hvac) {
        updates.push("checklist_hvac = ?");
        params.push(checklist.hvac);
      }
    }
    if (notes !== undefined) {
      updates.push("notes = ?");
      params.push(notes);
    }
    if (clientName) {
      updates.push("client_name = ?");
      params.push(clientName);
    }
    if (clientEmail) {
      updates.push("client_email = ?");
      params.push(clientEmail);
    }
    if (status) {
      updates.push("status = ?");
      params.push(status);
    }

    if (updates.length > 0) {
      params.push(inspectionId);
      await pool.query(
        `UPDATE inspections SET ${updates.join(", ")} WHERE inspection_id = ?`,
        params,
      );
    }

    // Handle images update
    if (images && Array.isArray(images)) {
      // Delete existing and insert new
      await pool.query(
        "DELETE FROM inspection_images WHERE inspection_id = ?",
        [inspectionId],
      );
      for (const img of images) {
        await pool.query(
          "INSERT INTO inspection_images (image_id, inspection_id, s3_key, file_name) VALUES (?, ?, ?, ?)",
          [img.imageId, inspectionId, img.s3Key, img.fileName || "image.jpg"],
        );
      }
    }

    // Return updated inspection
    const [rows] = await pool.query(
      "SELECT * FROM inspections WHERE inspection_id = ?",
      [inspectionId],
    );
    const [imgRows] = await pool.query(
      "SELECT image_id, s3_key, file_name FROM inspection_images WHERE inspection_id = ?",
      [inspectionId],
    );

    res.json({
      message: "Inspection updated successfully",
      inspection: formatInspection(rows[0], imgRows),
    });
  } catch (error) {
    console.error("Update inspection error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// ==================== PRESIGNED URL ROUTE ====================

app.post("/api/presigned-url", async (req, res) => {
  try {
    const { inspectionId, fileName, contentType, operation } = req.body;

    if (!inspectionId || !fileName) {
      return res
        .status(400)
        .json({ error: "Missing required fields: inspectionId, fileName" });
    }

    const imageId = `img_${randomUUID().slice(0, 8)}`;
    const ext = fileName.split(".").pop();
    const s3Key = `inspections/${inspectionId}/${imageId}.${ext}`;

    if (operation === "download") {
      const command = new GetObjectCommand({
        Bucket: IMAGE_BUCKET,
        Key: req.body.s3Key || s3Key,
      });
      const url = await getSignedUrl(s3Client, command, { expiresIn: 3600 });
      res.json({ downloadUrl: url, s3Key, imageId, expiresIn: 3600 });
    } else {
      const command = new PutObjectCommand({
        Bucket: IMAGE_BUCKET,
        Key: s3Key,
        ContentType: contentType || "image/jpeg",
      });
      const url = await getSignedUrl(s3Client, command, { expiresIn: 300 });
      res.json({ uploadUrl: url, s3Key, imageId, expiresIn: 300 });
    }
  } catch (error) {
    console.error("Presigned URL error:", error);
    res
      .status(500)
      .json({ error: "Internal server error", details: error.message });
  }
});

// Helper: Format inspection for API response
function formatInspection(row, images = []) {
  return {
    inspectionId: row.inspection_id,
    propertyAddress: row.property_address,
    inspectorName: row.inspector_name,
    inspectorEmail: row.inspector_email,
    clientName: row.client_name,
    clientEmail: row.client_email,
    status: row.status,
    checklist: {
      roof: row.checklist_roof,
      foundation: row.checklist_foundation,
      plumbing: row.checklist_plumbing,
      electrical: row.checklist_electrical,
      hvac: row.checklist_hvac,
    },
    notes: row.notes,
    images: images.map((img) => ({
      imageId: img.image_id,
      s3Key: img.s3_key,
      fileName: img.file_name,
    })),
    reportGeneratedAt: row.report_generated_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

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
  console.log(`Inspection API running on port ${PORT}`);
  console.log(`Database Host: ${process.env.DB_HOST || "localhost"}`);
  console.log(`S3 Bucket: ${IMAGE_BUCKET}`);
});

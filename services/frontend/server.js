const dotenv = require("dotenv");
const express = require("express");
const path = require("path");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();
dotenv.config();
const PORT = process.env.PORT || 8080;

const INSPECTION_API_URL = process.env.INSPECTION_API_URL;
const REPORT_API_URL = process.env.REPORT_API_URL;

// Validate environment variables
if (!INSPECTION_API_URL) {
  console.error("⚠️  WARNING: INSPECTION_API_URL is not set!");
  console.error("Environment variables:", process.env);
} else {
  console.log("✓ Proxying /api/inspections to:", INSPECTION_API_URL);
}

if (!REPORT_API_URL) {
  console.error("⚠️  WARNING: REPORT_API_URL is not set!");
} else {
  console.log("✓ Proxying /api/reports to:", REPORT_API_URL);
}

// Proxy API requests to backend services
// Mount at /api to proxy all API requests and preserve the full path
if (INSPECTION_API_URL) {
  // Proxy inspection API requests to backend
  app.use(
    "/api",
    createProxyMiddleware({
      target: INSPECTION_API_URL,
      changeOrigin: true,
      logLevel: "debug",
      // Filter: only proxy /api/inspections* and /api/presigned-url
      filter: (pathname, req) => {
        return (
          pathname.startsWith("/api/inspections") ||
          pathname.startsWith("/api/presigned-url")
        );
      },
      onError: (err, req, res) => {
        console.error("Proxy Error [inspection-api]:", err.message);
        res.status(502).json({
          error: "Bad Gateway",
          message: "Unable to reach inspection API",
        });
      },
    }),
  );
}

if (REPORT_API_URL) {
  // Proxy report service requests to backend
  app.use(
    "/api",
    createProxyMiddleware({
      target: REPORT_API_URL,
      changeOrigin: true,
      // Filter: only proxy /api/reports*
      filter: (pathname, req) => {
        return pathname.startsWith("/api/reports");
      },
      onError: (err, req, res) => {
        console.error("Proxy Error [report-service]:", err.message);
        res.status(502).json({
          error: "Bad Gateway",
          message: "Unable to reach report service",
        });
      },
    }),
  );
}

// Fallback for unconfigured API routes
app.use("/api/*", (req, res) => {
  res.status(503).json({
    error: "Service Unavailable",
    message: "API service not configured",
  });
});

// Serve static files from dist folder
app.use(express.static(path.join(__dirname, "dist")));

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "frontend" });
});

// SPA fallback - serve index.html for all other routes
app.use((req, res) => {
  res.sendFile(path.join(__dirname, "dist", "index.html"));
});

app.listen(PORT, () => {
  console.log(`Frontend server running on port ${PORT}`);
  console.log(`Serving static files from: ${path.join(__dirname, "dist")}`);
});

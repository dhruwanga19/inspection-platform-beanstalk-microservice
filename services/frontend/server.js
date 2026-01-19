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
// Note: Mounting at /api and forwarding to backends that also have /api prefix
if (INSPECTION_API_URL) {
  app.use(
    "/api/inspections",
    createProxyMiddleware({
      target: INSPECTION_API_URL,
      changeOrigin: true,
      pathRewrite: {
        "^/api": "/api", // Preserve the /api prefix
      },
      logLevel: "debug",
      onError: (err, req, res) => {
        console.error("Proxy Error [/api/inspections]:", err.message);
        res.status(502).json({
          error: "Bad Gateway",
          message: "Unable to reach inspection API",
        });
      },
    }),
  );

  app.use(
    "/api/presigned-url",
    createProxyMiddleware({
      target: INSPECTION_API_URL,
      changeOrigin: true,
      pathRewrite: {
        "^/api": "/api", // Preserve the /api prefix
      },
      onError: (err, req, res) => {
        console.error("Proxy Error [/api/presigned-url]:", err.message);
        res.status(502).json({
          error: "Bad Gateway",
          message: "Unable to reach inspection API",
        });
      },
    }),
  );
} else {
  app.use("/api/inspections", (req, res) => {
    res.status(503).json({
      error: "Service Unavailable",
      message: "INSPECTION_API_URL not configured",
    });
  });
  app.use("/api/presigned-url", (req, res) => {
    res.status(503).json({
      error: "Service Unavailable",
      message: "INSPECTION_API_URL not configured",
    });
  });
}

if (REPORT_API_URL) {
  app.use(
    "/api/reports",
    createProxyMiddleware({
      target: REPORT_API_URL,
      changeOrigin: true,
      pathRewrite: {
        "^/api": "/api", // Preserve the /api prefix
      },
      onError: (err, req, res) => {
        console.error("Proxy Error [/api/reports]:", err.message);
        res.status(502).json({
          error: "Bad Gateway",
          message: "Unable to reach report service",
        });
      },
    }),
  );
} else {
  app.use("/api/reports", (req, res) => {
    res.status(503).json({
      error: "Service Unavailable",
      message: "REPORT_API_URL not configured",
    });
  });
}

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

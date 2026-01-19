const express = require("express");
const path = require("path");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();
const PORT = process.env.PORT || 8080;

const INSPECTION_API_URL = process.env.INSPECTION_API_URL;
const REPORT_API_URL = process.env.REPORT_API_URL;

console.log("Proxying /api/inspections to:", INSPECTION_API_URL);
console.log("Proxying /api/reports to:", REPORT_API_URL);

// Proxy API requests to backend services
app.use(
  "/api/inspections",
  createProxyMiddleware({
    target: INSPECTION_API_URL,
    changeOrigin: true,
    logLevel: "debug",
  }),
);

app.use(
  "/api/presigned-url",
  createProxyMiddleware({
    target: INSPECTION_API_URL,
    changeOrigin: true,
  }),
);

app.use(
  "/api/reports",
  createProxyMiddleware({
    target: REPORT_API_URL,
    changeOrigin: true,
  }),
);

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

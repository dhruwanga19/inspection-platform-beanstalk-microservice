const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 8080;

// NOTE: With shared ALB and path-based routing, API requests are routed
// directly to backend services by the load balancer. No proxy needed.
// - /api/inspections/* -> Inspection API (port 3001)
// - /api/reports/* -> Report Service (port 3002)
// - /* -> Frontend (this server)

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

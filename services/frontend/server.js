const express = require("express");
const path = require("path");

const app = express();
// Elastic Beanstalk sets PORT environment variable, default to 8080 for local dev
const PORT = process.env.PORT || 8080;

// Serve static files from dist folder
app.use(express.static(path.join(__dirname, "dist")));

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({ status: "healthy", service: "frontend" });
});

// SPA fallback - serve index.html for all other routes
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "dist", "index.html"));
});

app.listen(PORT, () => {
  console.log(`Frontend server running on port ${PORT}`);
});

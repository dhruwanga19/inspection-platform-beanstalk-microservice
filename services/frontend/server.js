const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 8080;

// Log all requests for debugging
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  next();
});

// Serve static files from dist folder with proper MIME types
app.use(
  express.static(path.join(__dirname, "dist"), {
    setHeaders: (res, filePath) => {
      if (filePath.endsWith(".js")) {
        res.setHeader("Content-Type", "application/javascript");
      } else if (filePath.endsWith(".css")) {
        res.setHeader("Content-Type", "text/css");
      }
    },
  }),
);

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

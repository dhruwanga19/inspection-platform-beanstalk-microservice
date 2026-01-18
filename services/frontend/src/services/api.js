// services/frontend/src/services/api.js
// API Service for Inspection Platform - Updated for ECS deployment
// Uses relative URLs since nginx proxies API requests

// In ECS deployment, API calls go through the same ALB
// Frontend served at / and API at /api/*
const API_BASE = "/api";

class ApiService {
  async request(endpoint, options = {}) {
    const url = `${API_BASE}${endpoint}`;
    const config = {
      headers: {
        "Content-Type": "application/json",
        ...options.headers,
      },
      ...options,
    };

    try {
      console.log(`API Request: ${options.method || "GET"} ${url}`);
      const response = await fetch(url, config);
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "API request failed");
      }

      return data;
    } catch (error) {
      console.error(`API Error [${endpoint}]:`, error);
      throw error;
    }
  }

  // Create a new inspection
  async createInspection(inspectionData) {
    return this.request("/inspections", {
      method: "POST",
      body: JSON.stringify(inspectionData),
    });
  }

  // Get single inspection by ID
  async getInspection(inspectionId) {
    return this.request(`/inspections/${inspectionId}`);
  }

  // List all inspections (optionally filter by status)
  async listInspections(status = null) {
    const query = status ? `?status=${status}` : "";
    return this.request(`/inspections${query}`);
  }

  // Update an inspection
  async updateInspection(inspectionId, updates) {
    return this.request(`/inspections/${inspectionId}`, {
      method: "PUT",
      body: JSON.stringify(updates),
    });
  }

  // Generate report for inspection
  // Note: This now goes to the report-service via /api/reports/
  async generateReport(inspectionId) {
    return this.request(`/reports/${inspectionId}`, {
      method: "POST",
    });
  }

  // Get presigned URL for image upload
  async getPresignedUrl(inspectionId, fileName, contentType = "image/jpeg") {
    return this.request("/presigned-url", {
      method: "POST",
      body: JSON.stringify({
        inspectionId,
        fileName,
        contentType,
        operation: "upload",
      }),
    });
  }

  // Upload image to S3 using presigned URL
  async uploadImage(inspectionId, file) {
    const { uploadUrl, s3Key, imageId } = await this.getPresignedUrl(
      inspectionId,
      file.name,
      file.type
    );

    const uploadResponse = await fetch(uploadUrl, {
      method: "PUT",
      headers: { "Content-Type": file.type },
      body: file,
    });

    if (!uploadResponse.ok) {
      throw new Error("Failed to upload image to S3");
    }

    return {
      imageId,
      s3Key,
      description: file.name,
      uploadedAt: new Date().toISOString(),
    };
  }

  // Upload multiple images
  async uploadImages(inspectionId, files) {
    return Promise.all(
      files.map((file) => this.uploadImage(inspectionId, file))
    );
  }
}

export const api = new ApiService();

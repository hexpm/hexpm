/**
 * DownloadButton Hook
 * 
 * Handles downloading recovery codes or other data as a text file.
 * 
 * Usage:
 * <button phx-hook="DownloadButton" data-download-target="element-id">
 *   Download
 * </button>
 * 
 * The target element should have a data-value attribute with the text to download.
 */
export const DownloadButton = {
  mounted() {
    this.boundHandleDownload = this.handleDownload.bind(this);
    this.el.addEventListener("click", this.boundHandleDownload);
  },

  destroyed() {
    if (this.boundHandleDownload) {
      this.el.removeEventListener("click", this.boundHandleDownload);
    }
  },

  handleDownload(event) {
    event.preventDefault();
    
    const targetId = this.el.dataset.downloadTarget;
    const targetElement = document.getElementById(targetId);
    
    if (!targetElement) {
      console.error(`Download target element not found: ${targetId}`);
      return;
    }

    const textToDownload = targetElement.dataset.value;
    
    if (!textToDownload) {
      console.error(`No data-value found on target element: ${targetId}`);
      return;
    }

    // Create file content with header
    const fileContent = `Hex.pm Recovery Codes
Generated: ${new Date().toLocaleString()}

${textToDownload}

IMPORTANT: Store these codes in a secure location.
Each code can only be used once.
`;

    // Create blob and download
    const blob = new Blob([fileContent], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    
    // Create temporary link and trigger download
    const link = document.createElement("a");
    link.href = url;
    link.download = `hex-recovery-codes-${Date.now()}.txt`;
    
    // Trigger download
    document.body.appendChild(link);
    link.click();
    
    // Cleanup
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
};

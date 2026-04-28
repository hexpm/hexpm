/**
 * PrintButton Hook
 * 
 * Handles printing recovery codes or other data.
 * Opens a print dialog with formatted content.
 * 
 * Usage:
 * <button phx-hook="PrintButton" data-print-target="element-id">
 *   Print
 * </button>
 * 
 * The target element should have a data-value attribute with the text to print.
 */
export const PrintButton = {
  mounted() {
    this.boundHandlePrint = this.handlePrint.bind(this);
    this.el.addEventListener("click", this.boundHandlePrint);
  },

  destroyed() {
    if (this.boundHandlePrint) {
      this.el.removeEventListener("click", this.boundHandlePrint);
    }
  },

  handlePrint(event) {
    event.preventDefault();
    
    const targetId = this.el.dataset.printTarget;
    const targetElement = document.getElementById(targetId);
    
    if (!targetElement) {
      console.error(`Print target element not found: ${targetId}`);
      return;
    }

    const textToPrint = targetElement.dataset.value;
    
    if (!textToPrint) {
      console.error(`No data-value found on target element: ${targetId}`);
      return;
    }

    // Create a new window for printing
    const printWindow = window.open("", "", "width=600,height=400");
    
    if (!printWindow) {
      console.error("Failed to open print window. Popup might be blocked.");
      alert("Please allow popups to print recovery codes.");
      return;
    }

    // Create styled print content
    const printContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <title>Recovery Codes - Hex.pm</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
              padding: 40px;
              max-width: 600px;
              margin: 0 auto;
            }
            h1 {
              font-size: 24px;
              margin-bottom: 20px;
              color: #1a202c;
            }
            .codes {
              white-space: pre-line;
              font-family: 'Monaco', 'Courier New', monospace;
              font-size: 14px;
              line-height: 1.8;
              background: #f7fafc;
              padding: 20px;
              border-radius: 8px;
              border: 1px solid #e2e8f0;
            }
            .footer {
              margin-top: 30px;
              padding-top: 20px;
              border-top: 1px solid #e2e8f0;
              color: #718096;
              font-size: 12px;
            }
            @media print {
              body {
                padding: 20px;
              }
            }
          </style>
        </head>
        <body>
          <h1>Hex.pm Recovery Codes</h1>
          <p>Store these recovery codes in a secure location. Each code can only be used once.</p>
          <div class="codes">${textToPrint}</div>
          <div class="footer">
            <p>Generated on ${new Date().toLocaleDateString()}</p>
            <p>Keep these codes safe and secure.</p>
          </div>
        </body>
      </html>
    `;

    printWindow.document.write(printContent);
    printWindow.document.close();
    
    // Wait for content to load, then print
    printWindow.onload = function() {
      printWindow.focus();
      printWindow.print();
      // Close window after printing (user can cancel)
      setTimeout(() => {
        printWindow.close();
      }, 100);
    };
  }
};

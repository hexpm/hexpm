let scriptPromise;

function loadHCaptcha() {
  if (window.hcaptcha) return Promise.resolve();
  if (scriptPromise) return scriptPromise;

  scriptPromise = new Promise((resolve, reject) => {
    window.hexpmHCaptchaLoaded = resolve;

    const script = document.createElement("script");
    script.src =
      "https://js.hcaptcha.com/1/api.js?onload=hexpmHCaptchaLoaded&render=explicit";
    script.async = true;
    script.defer = true;
    script.addEventListener("error", reject, { once: true });
    document.head.appendChild(script);
  });

  return scriptPromise;
}

export const HCaptcha = {
  mounted() {
    this.widgetId = null;

    loadHCaptcha().then(() => {
      if (!this.el.isConnected) return;

      this.widgetId = window.hcaptcha.render(this.el, {
        sitekey: this.el.dataset.sitekey,
        theme: document.documentElement.dataset.theme || "light",
      });
    }).catch(() => {});

    this.handleEvent("reset-hcaptcha", () => {
      if (this.widgetId !== null && window.hcaptcha) {
        window.hcaptcha.reset(this.widgetId);
      }
    });
  },
};

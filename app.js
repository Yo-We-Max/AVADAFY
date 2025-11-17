// ========= CONFIG =========

// Choose how the contact form should behave:
//   "formsubmit" -> simple HTML POST to Formsubmit.co
//   "netlify"   -> Netlify Forms (when deployed on Netlify)
//   "emailjs"   -> send via EmailJS using JS only
const CONTACT_PROVIDER = "formsubmit"; // change this to "netlify" or "emailjs"

// EmailJS config (only used if CONTACT_PROVIDER === "emailjs")
// 1. Go to https://www.emailjs.com/
// 2. Create a service and a template
// 3. Replace the placeholders below
const EMAILJS_CONFIG = {
  publicKey: "YOUR_EMAILJS_PUBLIC_KEY",
  serviceId: "YOUR_SERVICE_ID",
  templateId: "YOUR_TEMPLATE_ID",
};

// ========= ROUTER =========

const routes = document.querySelectorAll("[data-route]");
const navLinks = document.querySelectorAll("[data-link]");

function setRoute(routeName) {
  // Update sections
  routes.forEach((section) => {
    const isActive = section.dataset.route === routeName;
    section.classList.toggle("route-active", isActive);
  });

  // Update nav states
  navLinks.forEach((link) => {
    const hash = link.getAttribute("href").replace("#", "");
    link.classList.toggle("nav-active", hash === routeName);
  });

  // Scroll to top of main content
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function handleHashChange() {
  const hash = window.location.hash.replace("#", "") || "home";
  setRoute(hash);
}

window.addEventListener("hashchange", handleHashChange);

// Nav click: set hash (URL) and route
navLinks.forEach((link) => {
  link.addEventListener("click", (e) => {
    e.preventDefault();
    const target = link.getAttribute("href");
    if (target) {
      window.location.hash = target;
    }
  });
});

// ========= THEME TOGGLE =========

const THEME_KEY = "avadafy-theme";
const themeToggleBtn = document.getElementById("themeToggle");

function applyTheme(theme) {
  if (theme === "light") {
    document.body.classList.add("theme-light");
    document.body.classList.remove("theme-dark");
  } else {
    document.body.classList.add("theme-dark");
    document.body.classList.remove("theme-light");
  }
}

function initTheme() {
  const stored = localStorage.getItem(THEME_KEY);

  if (stored === "light" || stored === "dark") {
    applyTheme(stored);
    return;
  }

  // Default: respect system preference
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  applyTheme(prefersDark ? "dark" : "light");
}

themeToggleBtn.addEventListener("click", () => {
  const isLight = document.body.classList.contains("theme-light");
  const nextTheme = isLight ? "dark" : "light";
  applyTheme(nextTheme);
  localStorage.setItem(THEME_KEY, nextTheme);
});

// ========= HERO CTA / ROUTE SHORTCUTS =========

const ctaStart = document.getElementById("ctaStart");
const ctaTour = document.getElementById("ctaTour");

if (ctaStart) {
  ctaStart.addEventListener("click", () => {
    window.location.hash = "#features";
  });
}

if (ctaTour) {
  ctaTour.addEventListener("click", () => {
    window.location.hash = "#studio";
  });
}

// ========= ANIMATED COUNTERS =========

const counterElements = document.querySelectorAll(".metric");

function animateCounter(el) {
  const target = parseFloat(el.dataset.counter || "0");
  const valueEl = el.querySelector(".metric-value");
  let current = 0;
  const duration = 1200;
  const start = performance.now();

  function tick(now) {
    const progress = Math.min((now - start) / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3); // ease-out
    current = target * eased;

    valueEl.textContent =
      target % 1 === 0 ? Math.round(current) : current.toFixed(1);

    if (progress < 1) {
      requestAnimationFrame(tick);
    }
  }

  requestAnimationFrame(tick);
}

// ========= TESTIMONIAL CAROUSEL =========

const testimonials = document.querySelectorAll(".testimonial");
const dots = document.querySelectorAll(".testimonial-dots .dot");
let currentSlide = 0;
let slideTimer;

function showSlide(index) {
  currentSlide = index;
  testimonials.forEach((t, i) => {
    t.classList.toggle("active", i === index);
  });
  dots.forEach((d, i) => d.classList.toggle("active", i === index));
}

function startSlideTimer() {
  clearInterval(slideTimer);
  slideTimer = setInterval(() => {
    const next = (currentSlide + 1) % testimonials.length;
    showSlide(next);
  }, 6000);
}

dots.forEach((dot) => {
  dot.addEventListener("click", () => {
    const slide = parseInt(dot.dataset.slide, 10);
    showSlide(slide);
    startSlideTimer();
  });
});

// ========= BILLING TOGGLE =========

const billingSwitch = document.getElementById("billingSwitch");
const priceEls = document.querySelectorAll(".pricing-amount");

function updateBillingMode(mode) {
  document.body.dataset.billing = mode;

  priceEls.forEach((el) => {
    const monthly = el.dataset.monthly;
    const yearly = el.dataset.yearly;
    const value = mode === "yearly" ? yearly || monthly : monthly;
    el.textContent = value;
  });

  document
    .querySelectorAll("[data-billing-label]")
    .forEach((labelEl) => {
      const labelMode = labelEl.dataset.billingLabel;
      labelEl.classList.toggle("billing-label-active", labelMode === mode);
    });
}

if (billingSwitch) {
  billingSwitch.addEventListener("click", () => {
    const nextMode =
      document.body.dataset.billing === "yearly" ? "monthly" : "yearly";
    updateBillingMode(nextMode);
  });
}

// ========= SCROLL REVEAL =========

const animatedEls = document.querySelectorAll("[data-animate]");

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("animate-in");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.14 }
);

animatedEls.forEach((el) => observer.observe(el));

// ========= CONTACT FORM =========

const contactForm = document.getElementById("contactForm");
const formStatus = document.getElementById("formStatus");

function showError(fieldId, message) {
  const span = document.querySelector(`.error[data-for="${fieldId}"]`);
  if (span) span.textContent = message;
}

function clearErrors() {
  document.querySelectorAll(".error").forEach((span) => {
    span.textContent = "";
  });
  if (formStatus) {
    formStatus.textContent = "";
    formStatus.style.color = "";
  }
}

function setStatus(message, type = "info") {
  if (!formStatus) return;
  formStatus.textContent = message;
  formStatus.style.color =
    type === "error" ? "#fb7185" : type === "success" ? "#4ade80" : "";
}

// Initialize EmailJS if chosen
function maybeInitEmailJS() {
  if (CONTACT_PROVIDER !== "emailjs") return;
  if (!window.emailjs) return;

  emailjs.init(EMAILJS_CONFIG.publicKey);
}

if (contactForm) {
  contactForm.addEventListener("submit", async (e) => {
    clearErrors();

    const name = contactForm.name.value.trim();
    const email = contactForm.email.value.trim();
    const topic = contactForm.topic.value;
    const message = contactForm.message.value.trim();

    let hasError = false;

    if (!name) {
      showError("name", "Please enter your name.");
      hasError = true;
    }
    if (!email) {
      showError("email", "Please enter your email.");
      hasError = true;
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      showError("email", "Please enter a valid email address.");
      hasError = true;
    }
    if (!message) {
      showError("message", "Please enter a message.");
      hasError = true;
    }

    if (hasError) {
      e.preventDefault();
      setStatus("Please fix the errors above and try again.", "error");
      return;
    }

    // Provider-specific behaviour
    if (CONTACT_PROVIDER === "formsubmit" || CONTACT_PROVIDER === "netlify") {
      // Let the browser submit the form normally (redirect to Thank You page handled by provider)
      setStatus("Sending message…", "info");
      // no e.preventDefault here
      return;
    }

    if (CONTACT_PROVIDER === "emailjs") {
      e.preventDefault();
      if (!window.emailjs) {
        setStatus("EmailJS script not loaded. Check your connection.", "error");
        return;
      }

      setStatus("Sending via EmailJS…", "info");

      try {
        await emailjs.send(EMAILJS_CONFIG.serviceId, EMAILJS_CONFIG.templateId, {
          from_name: name,
          from_email: email,
          topic,
          message,
        });

        setStatus("Message sent! Check your inbox for a confirmation.", "success");
        contactForm.reset();
      } catch (err) {
        console.error(err);
        setStatus(
          "Something went wrong sending your message. Double-check your EmailJS keys.",
          "error"
        );
      }
    }
  });
}

// ========= INIT =========

document.addEventListener("DOMContentLoaded", () => {
  initTheme();
  handleHashChange();
  maybeInitEmailJS();
  animateCounterElementsOnce();
  showSlide(0);
  startSlideTimer();
  updateBillingMode("monthly");
  const yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();
});

function animateCounterElementsOnce() {
  counterElements.forEach((el) => animateCounter(el));
}
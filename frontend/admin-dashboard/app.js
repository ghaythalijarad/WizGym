/* ── WizGym Admin Dashboard — JavaScript ── */
(() => {
  'use strict';

  // ── Config ──
  const config = window.WIZGYM_CONFIG || {};
  const API_BASE = config.api?.baseUrl || 'https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1';

  const IS_DEV = config.features?.enableDevMode ?? (
    window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
  );

  // Get authentication token
  // Get authentication token — admin JWT stored by login.html
  function getAuthToken() {
    return sessionStorage.getItem('wizgym_admin_token');
  }

  function getHeaders() {
    const token = getAuthToken();
    return {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    };
  }

  // Check if user is authenticated — always require a real JWT
  function checkAuth() {
    if (!getAuthToken()) {
      window.location.href = "login.html";
      return false;
    }
    return true;
  }

  // Logout function
  function logout() {
    sessionStorage.removeItem("wizgym_admin_token");
    window.location.href = "login.html";
  }

  // ── DOM refs ──
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const sidebar = $("#sidebar");
  const main = $("#main");
  const content = $("#content");
  const pageTitle = $("#pageTitle");
  const refreshBtn = $("#refreshBtn");
  const menuToggle = $("#menuToggle");
  const toastBox = $("#toastContainer");

  // ── State ──
  let currentPage = "dashboard";

  // ── Navigation ──
  $$(".nav-item").forEach((link) => {
    link.addEventListener("click", (e) => {
      // IMPORTANT: stop global click handlers / overlays from swallowing the click
      e.preventDefault();
      e.stopPropagation();

      const page = link.dataset.page;
      if (page) navigate(page);
    });
  });

  refreshBtn.addEventListener("click", () => navigate(currentPage));

  menuToggle.addEventListener("click", () => {
    sidebar.classList.toggle("open");
    main.classList.toggle("expanded");
  });

  // Check authentication on load
  if (!checkAuth()) {
    return;
  }

  // Setup logout button
  const logoutBtn = document.getElementById("logoutBtn");
  if (logoutBtn) {
    logoutBtn.addEventListener("click", () => {
      if (confirm("هل تريد تسجيل الخروج؟")) {
        logout();
      }
    });
  }

  // Display user info from token (if available)
  function displayUserInfo() {
    const token = getAuthToken();
    if (token) {
      try {
        const payload = JSON.parse(atob(token.split(".")[1]));
        const adminNameEl = document.getElementById("adminName");
        if (adminNameEl) {
          // Show phone number from JWT (admin login is phone-based)
          adminNameEl.textContent = payload.phone || payload.sub || "مشرف";
        }
      } catch (err) {
        console.error("Failed to decode token:", err);
      }
    }
  }

  displayUserInfo();

  function navigate(page) {
    currentPage = page;
    $$(".nav-item").forEach((n) =>
      n.classList.toggle("active", n.dataset.page === page)
    );

    const titles = {
      dashboard: "لوحة التحكم",
      gyms: "اعتماد النوادي",
      subscriptions: "إدارة الاشتراكات",
      notifications: "إرسال الإشعارات",
      settings: "الإعدادات",
    };
    pageTitle.textContent = titles[page] || page;

    // Close mobile sidebar
    sidebar.classList.remove("open");
    main.classList.remove("expanded");

    // Render
    const renderers = {
      dashboard: renderDashboard,
      gyms: renderGyms,
      subscriptions: renderSubscriptions,
      notifications: renderNotifications,
      settings: renderSettings,
    };
    (renderers[page] || renderDashboard)();
  }

  // ── API helpers ──
  async function api(path, opts = {}) {
    const url = `${API_BASE}/${path.replace(/^\//, "")}`;
    const headers = getHeaders();

    try {
      const res = await fetch(url, { headers, ...opts });

      // Handle unauthorized - redirect to login
      if (res.status === 401 || res.status === 403) {
        if (!IS_DEV) {
          toast("انتهت الجلسة. الرجاء تسجيل الدخول مرة أخرى.", "error");
          setTimeout(() => logout(), 2000);
        }
        throw new Error("غير مصرح. الرجاء تسجيل الدخول مرة أخرى.");
      }

      if (!res.ok) {
        let msg = res.statusText;
        try {
          const j = await res.json();
          msg = j.message || msg;
        } catch (_) {}
        throw new Error(`${res.status}: ${msg}`);
      }

      return res.json();
    } catch (err) {
      // Network errors
      if (
        err.message.includes("Failed to fetch") ||
        err.message.includes("NetworkError")
      ) {
        throw new Error("تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.");
      }
      throw err;
    }
  }

  function showLoader() {
    content.innerHTML =
      '<div class="loader-wrap"><div class="loader"></div></div>';
  }

  function toast(msg, type = "info") {
    const el = document.createElement("div");
    el.className = `toast ${type}`;
    el.innerHTML = `<span class="material-icons-round" style="font-size:18px">${type === "success" ? "check_circle" : type === "error" ? "error" : "info"}</span><span>${msg}</span>`;
    toastBox.appendChild(el);
    setTimeout(() => {
      el.style.opacity = "0";
      setTimeout(() => el.remove(), 350);
    }, 3500);
  }

  // ── Dashboard ──
  async function renderDashboard() {
    showLoader();
    try {
      const data = await api("admin/dashboard");
      const accents = ["amber", "lime", "lavender", "pink"];
      const icons = ["pending_actions", "store", "group", "card_membership"];
      const labels = [
        "طلبات نوادي معلقة",
        "إجمالي النوادي",
        "إجمالي المستخدمين",
        "الاشتراكات النشطة",
      ];
      const keys = [
        "pendingApprovals",
        "totalGyms",
        "totalUsers",
        "activeSubscriptions",
      ];

      content.innerHTML = `
        <div class="stats-grid">
          ${keys
            .map(
              (k, i) => `
            <div class="stat-card ${accents[i]}">
              <div class="stat-card-icon"><span class="material-icons-round">${icons[i]}</span></div>
              <div class="stat-card-value">${data[k] ?? 0}</div>
              <div class="stat-card-label">${labels[i]}</div>
            </div>
          `
            )
            .join("")}
        </div>
        <h2 class="section-title">الوصول السريع</h2>
        <p class="section-subtitle">انقر على بطاقة أعلاه أو استخدم القائمة الجانبية للتنقل.</p>
      `;

      // Click stat cards to navigate
      $$(".stat-card", content).forEach((card, i) => {
        card.style.cursor = "pointer";
        card.addEventListener("click", () =>
          navigate(i < 2 ? "gyms" : "subscriptions")
        );
      });
    } catch (e) {
      content.innerHTML = errorState("تعذر تحميل لوحة التحكم", e.message);
    }
  }

  // ── Gyms ──
  async function renderGyms() {
    showLoader();
    try {
      const gyms = await api("admin/gyms");
      if (!Array.isArray(gyms) || gyms.length === 0) {
        content.innerHTML = emptyState("store", "لا توجد طلبات نوادي حالياً");
        return;
      }
      content.innerHTML = `
        <h2 class="section-title">اعتماد النوادي</h2>
        <p class="section-subtitle">راجع الطلبات ووافق أو ارفض من هنا.</p>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>اسم النادي</th>
                <th>المالك</th>
                <th>المدينة</th>
                <th>تاريخ الطلب</th>
                <th>الحالة</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody id="gymsBody"></tbody>
          </table>
        </div>
      `;
      const tbody = $("#gymsBody");
      gyms.forEach((gym) => {
        const tr = document.createElement("tr");
        const status = (gym.status || "PENDING").toUpperCase();
        const chipClass =
          status === "APPROVED" || status === "ACTIVE"
            ? "green"
            : status === "REJECTED"
              ? "red"
              : "amber";
        const chipLabel =
          status === "APPROVED" || status === "ACTIVE"
            ? "نشط"
            : status === "REJECTED"
              ? "مرفوض"
              : "معلق";

        const canApprove = status !== "APPROVED" && status !== "ACTIVE";
        const canReject = status !== "REJECTED";

        tr.innerHTML = `
          <td style="font-weight:700">${esc(gym.gymName || "")}</td>
          <td>${esc(gym.ownerName || "")}</td>
          <td>${esc(gym.city || "")}</td>
          <td style="font-family:var(--font-en)">${dateOnly(gym.requestedAt)}</td>
          <td><span class="chip ${chipClass}">${chipLabel}</span></td>
          <td class="actions-cell">
            <div class="actions-cell-inner">
              <button class="btn btn-lime btn-sm approve-btn" ${canApprove ? "" : "disabled"}>اعتماد</button>
              <button class="btn btn-danger btn-sm reject-btn" ${canReject ? "" : "disabled"}>رفض</button>
            </div>
          </td>
        `;
        const approveBtn = tr.querySelector(".approve-btn");
        const rejectBtn = tr.querySelector(".reject-btn");
        if (canApprove)
          approveBtn.addEventListener("click", () => approveGym(gym.id));
        if (canReject)
          rejectBtn.addEventListener("click", () => rejectGym(gym.id));
        tbody.appendChild(tr);
      });
    } catch (e) {
      content.innerHTML = errorState("تعذر تحميل طلبات النوادي", e.message);
    }
  }

  async function approveGym(id) {
    try {
      await api(`admin/gyms/${id}/approve`, { method: "POST", body: "{}" });
      toast("تم اعتماد النادي بنجاح", "success");
      renderGyms();
    } catch (e) {
      toast("فشل اعتماد النادي: " + e.message, "error");
    }
  }

  async function rejectGym(id) {
    try {
      await api(`admin/gyms/${id}/reject`, {
        method: "POST",
        body: JSON.stringify({ note: "Rejected by admin" }),
      });
      toast("تم رفض طلب النادي", "success");
      renderGyms();
    } catch (e) {
      toast("فشل رفض الطلب: " + e.message, "error");
    }
  }

  // ── Subscriptions ──
  async function renderSubscriptions() {
    showLoader();
    try {
      const subs = await api("admin/subscriptions");
      const reqData = await api("admin/subscription-requests?status=PENDING");
      const requests = Array.isArray(reqData?.requests) ? reqData.requests : [];
      const planData = await api("admin/subscription-plans");
      const plans = Array.isArray(planData?.plans) ? planData.plans : [];

      if (
        (!Array.isArray(subs) || subs.length === 0) &&
        requests.length === 0 &&
        plans.length === 0
      ) {
        content.innerHTML = emptyState(
          "storefront",
          "لا توجد بيانات اشتراكات حالياً"
        );
        return;
      }

      content.innerHTML = `
        <h2 class="section-title">اشتراكات الاستوديوهات</h2>
        <p class="section-subtitle">إدارة خطط اشتراك المنصة + مراجعة طلبات الدفع (زين كاش) + تفعيل الاشتراكات.</p>

        <h3 class="section-title" style="margin-top:18px;font-size:18px">خطط اشتراك المنصة</h3>
        <p class="section-subtitle">هذه الخطط تظهر لمالك النادي في تطبيق الموبايل عند طلب التفعيل.</p>

        <div class="settings-card" style="margin-bottom:14px">
          <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:end">
            <div style="flex:1;min-width:120px">
              <label style="display:block;color:#bbb;font-size:12px;margin-bottom:6px">المدة (شهر)</label>
              <input id="planDuration" type="number" min="1" placeholder="مثال: 1" style="width:100%" />
            </div>
            <div style="flex:1;min-width:120px">
              <label style="display:block;color:#bbb;font-size:12px;margin-bottom:6px">السعر</label>
              <input id="planPrice" type="number" min="0" placeholder="مثال: 50000" style="width:100%" />
            </div>
            <div style="flex:1;min-width:120px">
              <label style="display:block;color:#bbb;font-size:12px;margin-bottom:6px">العملة</label>
              <select id="planCurrency" style="width:100%">
                <option value="IQD">IQD</option>
                <option value="USD">USD</option>
              </select>
            </div>
            <div>
              <button id="createPlanBtn" class="btn btn-success">
                <span class="material-icons-round" style="font-size:16px">add_circle</span>
                إضافة خطة
              </button>
            </div>
          </div>
        </div>

        <div class="table-wrap" style="margin-bottom:18px">
          <table>
            <thead>
              <tr>
                <th>المدة</th>
                <th>السعر</th>
                <th>الحالة</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody id="plansBody"></tbody>
          </table>
        </div>

        <h3 class="section-title" style="margin-top:24px;font-size:18px">طلبات تفعيل الاشتراك (بانتظار المراجعة)</h3>
        <p class="section-subtitle">راجع إثبات الدفع (سكرينشوت) ثم اضغط "اعتماد" لتفعيل الاشتراك.</p>
        <div class="table-wrap" style="margin-bottom:18px">
          <table>
            <thead>
              <tr>
                <th>النادي</th>
                <th>المالك</th>
                <th>الخطة</th>
                <th>الهاتف المستلم</th>
                <th>تاريخ الطلب</th>
                <th>إجراءات</th>
              </tr>
            </thead>
            <tbody id="subReqBody"></tbody>
          </table>
        </div>

        <h3 class="section-title" style="margin-top:24px;font-size:18px">الاشتراكات الحالية</h3>
        <div class="sub-cards" id="subCards"></div>

        <!-- Proof Viewer Modal -->
        <div id="proofModal" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:1000;align-items:center;justify-content:center">
          <div style="background:#1e1e28;border:1px solid rgba(202,252,1,.15);border-radius:20px;padding:18px;width:100%;max-width:560px;margin:24px">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:10px">
              <div>
                <div style="color:#fff;font-weight:800" id="proofTitle">إثبات الدفع</div>
                <div style="color:#888;font-size:12px" id="proofSubtitle"></div>
              </div>
              <button id="proofCloseBtn" class="btn" style="background:rgba(255,255,255,.06)">إغلاق</button>
            </div>
            <div style="background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:10px;min-height:220px;display:flex;align-items:center;justify-content:center">
              <img id="proofImg" alt="proof" style="max-width:100%;max-height:70vh;border-radius:10px;display:none" />
              <div id="proofLoading" class="loader" style="width:26px;height:26px"></div>
            </div>
          </div>
        </div>

        <!-- Activate Modal -->
        <div id="activateModal" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:1000;align-items:center;justify-content:center">
          <div style="background:#1e1e28;border:1px solid rgba(202,252,1,.15);border-radius:20px;padding:36px;width:100%;max-width:400px;margin:24px">
            <h3 style="color:#fff;font-size:18px;font-weight:700;margin-bottom:6px" id="modalGymName"></h3>
            <p style="color:#888;font-size:13px;margin-bottom:24px" id="modalGymCity"></p>
            <label style="display:block;font-size:13px;font-weight:600;color:#ccc;margin-bottom:8px">مدة الاشتراك</label>
            <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:24px" id="durationGrid"></div>
            <p style="font-size:13px;color:#888;margin-bottom:20px">
              ينتهي في: <strong style="color:#CAFC01" id="modalExpiry">—</strong>
            </p>
            <div style="display:flex;gap:10px">
              <button id="modalConfirmBtn" class="btn btn-success" style="flex:1;justify-content:center">
                <span class="material-icons-round" style="font-size:18px">check_circle</span> تفعيل
              </button>
              <button id="modalCancelBtn" class="btn" style="flex:1;justify-content:center;background:rgba(255,255,255,.06)">
                إلغاء
              </button>
            </div>
          </div>
        </div>
      `;

      // ---- Plans management ----
      const plansBody = $("#plansBody");
      const createPlanBtn = $("#createPlanBtn");
      const planDuration = $("#planDuration");
      const planPrice = $("#planPrice");
      const planCurrency = $("#planCurrency");

      function renderPlansTable() {
        if (!plansBody) return;
        if (plans.length === 0) {
          plansBody.innerHTML = `<tr><td colspan="4" style="color:#888;padding:14px">لا توجد خطط — أضف خطة من الأعلى</td></tr>`;
          return;
        }

        plansBody.innerHTML = "";
        plans.forEach((p) => {
          const isActive = p.isActive !== false;
          const tr = document.createElement("tr");
          tr.innerHTML = `
            <td>${esc((p.durationMonths || 1) + " شهر")}</td>
            <td>${esc((p.price || 0) + " " + (p.currency || "IQD"))}</td>
            <td><span class="chip ${isActive ? "green" : "red"}">${isActive ? "نشطة" : "موقوفة"}</span></td>
            <td>
              <div style="display:flex;gap:8px;flex-wrap:wrap">
                <button class="btn" data-action="edit" style="background:rgba(255,255,255,.06)">تعديل</button>
                <button class="btn" data-action="toggle" style="background:rgba(255,255,255,.06)">${isActive ? "إيقاف" : "تفعيل"}</button>
              </div>
            </td>
          `;

          tr.querySelector('[data-action="edit"]').addEventListener(
            "click",
            async () => {
              const newDur = prompt(
                "المدة (شهر):",
                String(p.durationMonths || 1)
              );
              if (newDur == null) return;
              const newPrice = prompt("السعر:", String(p.price || 0));
              if (newPrice == null) return;
              const newCurrency = prompt(
                "العملة (IQD أو USD):",
                String(p.currency || "IQD")
              );
              if (newCurrency == null) return;

              try {
                await api(`admin/subscription-plans/${p.planId}`, {
                  method: "PATCH",
                  body: JSON.stringify({
                    durationMonths: Number(newDur),
                    price: Number(newPrice),
                    currency: String(newCurrency).toUpperCase(),
                  }),
                });
                toast("تم تحديث الخطة", "success");
                renderSubscriptions();
              } catch (e) {
                toast("فشل تحديث الخطة: " + e.message, "error");
              }
            }
          );

          tr.querySelector('[data-action="toggle"]').addEventListener(
            "click",
            async () => {
              try {
                await api(`admin/subscription-plans/${p.planId}`, {
                  method: "PATCH",
                  body: JSON.stringify({ isActive: !isActive }),
                });
                toast(
                  isActive ? "تم إيقاف الخطة" : "تم تفعيل الخطة",
                  "success"
                );
                renderSubscriptions();
              } catch (e) {
                toast("فشل العملية: " + e.message, "error");
              }
            }
          );

          plansBody.appendChild(tr);
        });
      }

      renderPlansTable();

      createPlanBtn?.addEventListener("click", async () => {
        const dur = Number(planDuration?.value || 0);
        const price = Number(planPrice?.value || 0);
        const currency = String(planCurrency?.value || "IQD").toUpperCase();

        if (!dur || dur < 1) {
          toast("يرجى إدخال مدة صحيحة", "error");
          return;
        }

        try {
          await api("admin/subscription-plans", {
            method: "POST",
            body: JSON.stringify({ durationMonths: dur, price, currency }),
          });
          toast("تم إنشاء الخطة", "success");
          renderSubscriptions();
        } catch (e) {
          toast("فشل إنشاء الخطة: " + e.message, "error");
        }
      });

      // ---- Render subscription requests ----
      const reqBody = $("#subReqBody");
      const proofModal = $("#proofModal");
      const proofImg = $("#proofImg");
      const proofLoading = $("#proofLoading");
      const proofTitle = $("#proofTitle");
      const proofSubtitle = $("#proofSubtitle");
      const proofCloseBtn = $("#proofCloseBtn");

      function openProofModal(req, url) {
        proofTitle.textContent = "إثبات الدفع";
        proofSubtitle.textContent = `${req.gymId} • ${req.createdAt || ""}`;
        proofImg.style.display = "none";
        proofLoading.style.display = "block";
        proofModal.style.display = "flex";

        proofImg.onload = () => {
          proofLoading.style.display = "none";
          proofImg.style.display = "block";
        };
        proofImg.onerror = () => {
          proofLoading.style.display = "none";
          toast("تعذر تحميل صورة الإثبات", "error");
        };
        proofImg.src = url;
      }

      proofCloseBtn?.addEventListener(
        "click",
        () => (proofModal.style.display = "none")
      );
      proofModal?.addEventListener("click", (e) => {
        if (e.target === proofModal) proofModal.style.display = "none";
      });

      if (requests.length === 0) {
        reqBody.innerHTML = `<tr><td colspan="6" style="color:#888;padding:14px">لا توجد طلبات معلّقة</td></tr>`;
      } else {
        reqBody.innerHTML = "";
        requests.forEach((req) => {
          const tr = document.createElement("tr");
          const planLabel = `${req.durationMonths || 1} شهر • ${req.price || 0} ${req.currency || "IQD"}`;
          const createdAt = req.createdAt
            ? new Date(req.createdAt).toLocaleString("ar-IQ")
            : "—";

          tr.innerHTML = `
            <td>${esc(req.gymId)}</td>
            <td>${esc(req.ownerName || req.ownerId || "")}</td>
            <td>${esc(planLabel)}</td>
            <td style="font-family:var(--font-en)">${esc(req.transferToPhone || "07831367435")}</td>
            <td>${esc(createdAt)}</td>
            <td>
              <div style="display:flex;gap:8px;flex-wrap:wrap">
                <button class="btn" data-action="view" style="background:rgba(255,255,255,.06)">عرض الإثبات</button>
                <button class="btn btn-success" data-action="approve">اعتماد</button>
                <button class="btn btn-danger" data-action="reject" style="background:rgba(244,67,54,.12);color:#f44336;border:1px solid rgba(244,67,54,.25)">رفض</button>
              </div>
            </td>
          `;

          tr.querySelector('[data-action="view"]').addEventListener(
            "click",
            async () => {
              try {
                const view = await api(
                  `admin/subscription-requests/${req.gymId}/${req.requestId}/view-url`
                );
                const url = view?.url || req.screenshotUrl;
                if (!url) throw new Error("لا يوجد رابط للصورة");
                openProofModal(req, url);
              } catch (e) {
                toast("فشل عرض الإثبات: " + e.message, "error");
              }
            }
          );

          tr.querySelector('[data-action="approve"]').addEventListener(
            "click",
            async () => {
              if (!confirm("هل تريد اعتماد الطلب وتفعيل الاشتراك؟")) return;
              try {
                await api(
                  `admin/subscription-requests/${req.gymId}/${req.requestId}/approve`,
                  { method: "POST" }
                );
                toast("تم اعتماد الطلب وتفعيل الاشتراك", "success");
                renderSubscriptions();
              } catch (e) {
                toast("فشل الاعتماد: " + e.message, "error");
              }
            }
          );

          tr.querySelector('[data-action="reject"]').addEventListener(
            "click",
            async () => {
              const note = prompt("سبب الرفض (اختياري):") || "";
              if (!confirm("تأكيد رفض الطلب؟")) return;
              try {
                await api(
                  `admin/subscription-requests/${req.gymId}/${req.requestId}/reject`,
                  {
                    method: "POST",
                    body: JSON.stringify({ note }),
                  }
                );
                toast("تم رفض الطلب", "success");
                renderSubscriptions();
              } catch (e) {
                toast("فشل الرفض: " + e.message, "error");
              }
            }
          );

          reqBody.appendChild(tr);
        });
      }

      // ---- Existing subscription cards flow (unchanged) ----
      const modal = $("#activateModal");
      const modalGymName = $("#modalGymName");
      const modalGymCity = $("#modalGymCity");
      const durationGrid = $("#durationGrid");
      const modalExpiry = $("#modalExpiry");
      const modalConfirmBtn = $("#modalConfirmBtn");
      const modalCancelBtn = $("#modalCancelBtn");
      let selectedMonths = 1;
      let activeGymId = null;

      function buildDurationGrid(currentExpiry) {
        durationGrid.innerHTML = "";
        [1, 2, 3, 6, 9, 12].forEach((m) => {
          const btn = document.createElement("button");
          btn.textContent =
            m === 12
              ? "سنة"
              : m === 9
                ? "٩ أشهر"
                : m === 6
                  ? "٦ أشهر"
                  : m === 3
                    ? "٣ أشهر"
                    : m === 2
                      ? "شهران"
                      : "شهر";
          btn.style.cssText = `padding:10px 4px;border-radius:10px;border:1.5px solid;font-family:var(--font-ar);font-size:13px;font-weight:700;cursor:pointer;transition:all .15s;background:${m === selectedMonths ? "#CAFC01" : "rgba(255,255,255,.05)"};border-color:${m === selectedMonths ? "#CAFC01" : "rgba(255,255,255,.12)"};color:${m === selectedMonths ? "#0E0E12" : "#ccc"}`;
          btn.addEventListener("click", () => {
            selectedMonths = m;
            buildDurationGrid(currentExpiry);
            updateExpiry(currentExpiry);
          });
          durationGrid.appendChild(btn);
        });
      }

      function updateExpiry(currentExpiry) {
        // If currently active and not expired, extend from expiry; else from today
        const base =
          currentExpiry && new Date(currentExpiry) > new Date()
            ? new Date(currentExpiry)
            : new Date();
        const end = new Date(base);
        end.setMonth(end.getMonth() + selectedMonths);
        modalExpiry.textContent = end.toLocaleDateString("ar-IQ", {
          year: "numeric",
          month: "long",
          day: "numeric",
        });
      }

      function openModal(sub) {
        activeGymId = sub.gymId;
        selectedMonths = 1;
        modalGymName.textContent = sub.gymName;
        modalGymCity.textContent = sub.city || "";
        buildDurationGrid(sub.expiresAt);
        updateExpiry(sub.expiresAt);
        modal.style.display = "flex";
      }

      modalCancelBtn.addEventListener("click", () => {
        modal.style.display = "none";
      });
      modal.addEventListener("click", (e) => {
        if (e.target === modal) modal.style.display = "none";
      });

      modalConfirmBtn.addEventListener("click", async () => {
        if (!activeGymId) return;
        modalConfirmBtn.disabled = true;
        modalConfirmBtn.innerHTML =
          '<div class="spinner" style="width:18px;height:18px;border-width:2px;border-color:rgba(0,0,0,.2);border-top-color:#0E0E12"></div>';
        try {
          await api(`admin/subscriptions/${activeGymId}/activate`, {
            method: "POST",
            body: JSON.stringify({ durationMonths: selectedMonths }),
          });
          modal.style.display = "none";
          toast(`✓ تم تفعيل الاشتراك لمدة ${selectedMonths} شهر`, "success");
          renderSubscriptions();
        } catch (e) {
          toast("فشل التفعيل: " + e.message, "error");
          modalConfirmBtn.disabled = false;
          modalConfirmBtn.innerHTML =
            '<span class="material-icons-round" style="font-size:18px">check_circle</span> تفعيل';
        }
      });

      const cards = $("#subCards");
      subs.forEach((sub) => {
        const status = (sub.status || "INACTIVE").toUpperCase();
        const isActive = status === "ACTIVE";
        const now = new Date();
        const expiry = sub.expiresAt ? new Date(sub.expiresAt) : null;
        const start = sub.startsAt ? new Date(sub.startsAt) : null;

        // Days remaining
        let daysLeft = "";
        let urgencyColor = "#CAFC01";
        if (isActive && expiry) {
          const days = Math.ceil((expiry - now) / (1000 * 60 * 60 * 24));
          daysLeft = days;
          if (days <= 7) urgencyColor = "#f44336";
          else if (days <= 30) urgencyColor = "#ff9800";
        }

        // Progress bar width
        let progressPct = 0;
        if (isActive && start && expiry) {
          const totalDays = Math.ceil((expiry - start) / (1000 * 60 * 60 * 24));
          const elapsedDays = Math.ceil((now - start) / (1000 * 60 * 60 * 24));
          progressPct = Math.min(
            100,
            Math.max(0, (elapsedDays / totalDays) * 100)
          );
        }

        const card = document.createElement("div");
        card.className = "sub-card";
        card.innerHTML = `
          <div class="sub-card-header">
            <div class="sub-card-title">${esc(sub.gymName)}</div>
            <div class="sub-card-status ${isActive ? "active" : "inactive"}">${isActive ? "نشط" : "غير نشط"}</div>
          </div>
          <div class="sub-card-body">
            <div class="sub-card-info">
              <div class="sub-card-info-item">
                <span class="sub-card-info-label">المالك:</span>
                <span class="sub-card-info-value">${esc(sub.ownerName || sub.ownerId || "")}</span>
              </div>
              <div class="sub-card-info-item">
                <span class="sub-card-info-label">المدينة:</span>
                <span class="sub-card-info-value">${esc(sub.city || "")}</span>
              </div>
              <div class="sub-card-info-item">
                <span class="sub-card-info-label">تاريخ البدء:</span>
                <span class="sub-card-info-value">${start ? start.toLocaleDateString("ar-IQ") : "—"}</span>
              </div>
              <div class="sub-card-info-item">
                <span class="sub-card-info-label">تاريخ الانتهاء:</span>
                <span class="sub-card-info-value">${expiry ? expiry.toLocaleDateString("ar-IQ") : "—"}</span>
              </div>
              <div class="sub-card-info-item">
                <span class="sub-card-info-label">الأيام المتبقية:</span>
                <span class="sub-card-info-value" style="color:${urgencyColor}">${daysLeft}</span>
              </div>
            </div>
            <div class="sub-card-progress">
              <div class="sub-card-progress-bar" style="width:${progressPct}%"></div>
            </div>
          </div>
          <div class="sub-card-footer">
            <button class="btn btn-lime" ${isActive ? "disabled" : ""}>تفعيل</button>
          </div>
        `;

        card
          .querySelector(".btn-lime")
          .addEventListener("click", () => openModal(sub));
        cards.appendChild(card);
      });
    } catch (e) {
      content.innerHTML = errorState("تعذر تحميل الاشتراكات", e.message);
    }
  }

  // ── Notifications ──
  async function renderNotifications() {
    showLoader();
    try {
      const [roles, broadcasts] = await Promise.all([
        api("notifications/roles"),
        api("notifications/broadcasts"),
      ]);

      content.innerHTML = `
        <section class="section">
          <h2 class="section-title">
            <span class="material-icons-round" style="vertical-align:middle;margin-inline-end:8px;font-size:22px;color:var(--lavender)">notifications</span>
            إرسال إشعار
          </h2>
          <div class="settings-card">
            <div class="form-group">
              <label for="notif-title">العنوان</label>
              <input type="text" id="notif-title" placeholder="عنوان الإشعار" />
            </div>
            <div class="form-group">
              <label for="notif-msg">الرسالة</label>
              <textarea id="notif-msg" rows="4" placeholder="نص الرسالة"></textarea>
            </div>
            <div class="form-group">
              <label>المستهدفون</label>
              <div class="checkbox-group">
                <label><input type="checkbox" id="role-all" /> الجميع</label>
                ${roles.map((r) => `<label><input type="checkbox" class="role-check" value="${esc(r)}" /> ${esc(r)}</label>`).join("")}
              </div>
            </div>
            <button id="send-notif-btn" class="btn btn-lime">
              <span class="material-icons-round" style="font-size:18px;vertical-align:middle;margin-inline-end:4px">send</span>
              إرسال الإشعار
            </button>
          </div>
        </section>

        <section class="section" style="margin-top:32px">
          <h2 class="section-title">
            <span class="material-icons-round" style="vertical-align:middle;margin-inline-end:8px;font-size:22px;color:var(--lavender)">history</span>
            الإشعارات المرسلة (${broadcasts.length})
          </h2>
          ${
            broadcasts.length === 0
              ? emptyState(
                  "notifications_off",
                  "لا توجد إشعارات مرسلة حتى الآن"
                )
              : `<div class="table-wrap"><table class="data-table">
                <thead><tr>
                  <th>العنوان</th><th>الرسالة</th><th>المستهدفون</th><th>التاريخ</th>
                </tr></thead>
                <tbody>
                  ${broadcasts
                    .map(
                      (b) => `
                    <tr>
                      <td><strong>${esc(b.title)}</strong></td>
                      <td style="max-width:260px;white-space:normal">${esc(b.message)}</td>
                      <td>${esc((b.targetRoles || []).join(", "))}</td>
                      <td style="font-family:var(--font-en);font-size:.8rem">${dateOnly(b.createdAt)}</td>
                    </tr>`
                    )
                    .join("")}
                </tbody>
              </table></div>`
          }
        </section>
      `;

      document
        .getElementById("send-notif-btn")
        ?.addEventListener("click", async () => {
          const title = document.getElementById("notif-title").value.trim();
          const message = document.getElementById("notif-msg").value.trim();
          const allChecked = document.getElementById("role-all").checked;
          const roleChecks = [
            ...document.querySelectorAll(".role-check:checked"),
          ].map((c) => c.value);
          const targetRoles = allChecked ? ["ALL"] : roleChecks;

          if (!title) {
            toast("أدخل عنوان الإشعار", "error");
            return;
          }
          if (!message) {
            toast("أدخل نص الإشعار", "error");
            return;
          }
          if (!allChecked && roleChecks.length === 0) {
            toast("اختر المستهدفين", "error");
            return;
          }

          const btn = document.getElementById("send-notif-btn");
          btn.disabled = true;
          btn.textContent = "جاري الإرسال...";
          try {
            await api("notifications/broadcast", {
              method: "POST",
              body: JSON.stringify({ title, message, targetRoles }),
            });
            toast("تم إرسال الإشعار بنجاح ✓", "success");
            renderNotifications();
          } catch (e) {
            toast(`فشل الإرسال: ${e.message}`, "error");
            btn.disabled = false;
            btn.innerHTML =
              '<span class="material-icons-round" style="font-size:18px;vertical-align:middle;margin-inline-end:4px">send</span> إرسال الإشعار';
          }
        });
    } catch (e) {
      content.innerHTML = errorState("تعذر تحميل الإشعارات", e.message);
    }
  }

  // ── Settings ──
  async function renderSettings() {
    showLoader();
    try {
      const settings = await api("admin/settings");
      content.innerHTML = `
        <h2 class="section-title">الإعدادات</h2>
        <p class="section-subtitle">تحديث إعدادات النظام.</p>
        <div class="settings-card">
          <div class="form-group">
            <label for="setting1">إعداد 1</label>
            <input type="text" id="setting1" value="${esc(settings.setting1 || "")}" />
          </div>
          <div class="form-group">
            <label for="setting2">إعداد 2</label>
            <input type="text" id="setting2" value="${esc(settings.setting2 || "")}" />
          </div>
          <button id="save-settings-btn" class="btn btn-lime">حفظ الإعدادات</button>
        </div>
      `;

      document
        .getElementById("save-settings-btn")
        ?.addEventListener("click", async () => {
          const setting1 = document.getElementById("setting1").value.trim();
          const setting2 = document.getElementById("setting2").value.trim();

          try {
            await api("admin/settings", {
              method: "POST",
              body: JSON.stringify({ setting1, setting2 }),
            });
            toast("تم حفظ الإعدادات بنجاح ✓", "success");
          } catch (e) {
            toast(`فشل حفظ الإعدادات: ${e.message}`, "error");
          }
        });
    } catch (e) {
      content.innerHTML = errorState("تعذر تحميل الإعدادات", e.message);
    }
  }

  // ── Utilities ──
  function esc(str) { const d = document.createElement('div'); d.textContent = str; return d.innerHTML; }

  function dateOnly(val) {
    if (!val) return '-';
    const s = String(val);
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  function formatPrice(val) {
    const n = Number(val) || 0;
    return n.toLocaleString('en-US');
  }

  function errorState(title, detail) {
    return `
      <div class="empty-state" style="min-height:320px">
        <span class="material-icons-round" style="font-size:56px;color:var(--pink)">${'error_outline'}</span>
        <strong style="font-size:1.1rem">${esc(title)}</strong>
        <span style="font-size:.85rem;color:var(--text-secondary);max-width:400px;text-align:center">${esc(detail || '')}</span>
        <button class="btn btn-lime" onclick="location.reload()">إعادة المحاولة</button>
      </div>
    `;
  }

  function emptyState(icon, text) {
    return `
      <div class="empty-state">
        <span class="material-icons-round">${icon}</span>
        <span>${esc(text)}</span>
      </div>
    `;
  }

  // ── Init ──
  navigate('dashboard');
})();

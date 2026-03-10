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

    // Development mode: allow unauthenticated access with fake headers
    if (IS_DEV && !token) {
      return {
        'Content-Type': 'application/json',
        'x-user-role': 'ADMIN',
        'x-user-id': 'acc-admin-1',
        'x-user-name': 'Platform Admin (Dev Mode)',
      };
    }

    // Production: send admin JWT
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    };
  }

  // Check if user is authenticated
  function checkAuth() {
    if (!IS_DEV && !getAuthToken()) {
      window.location.href = 'login.html';
      return false;
    }
    return true;
  }

  // Logout function
  function logout() {
    sessionStorage.removeItem('wizgym_admin_token');
    window.location.href = 'login.html';
  }

  // ── DOM refs ──
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const sidebar    = $('#sidebar');
  const main       = $('#main');
  const content    = $('#content');
  const pageTitle  = $('#pageTitle');
  const refreshBtn = $('#refreshBtn');
  const menuToggle = $('#menuToggle');
  const toastBox   = $('#toastContainer');

  // ── State ──
  let currentPage = 'dashboard';

  // ── Navigation ──
  $$('.nav-item').forEach(link => {
    link.addEventListener('click', e => {
      e.preventDefault();
      const page = link.dataset.page;
      if (page) navigate(page);
    });
  });

  refreshBtn.addEventListener('click', () => navigate(currentPage));

  menuToggle.addEventListener('click', () => {
    sidebar.classList.toggle('open');
    main.classList.toggle('expanded');
  });

  // Check authentication on load
  if (!checkAuth()) {
    return;
  }

  // Setup logout button
  const logoutBtn = document.getElementById('logoutBtn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', () => {
      if (confirm('هل تريد تسجيل الخروج؟')) {
        logout();
      }
    });
  }

  // Display user info from token (if available)
  function displayUserInfo() {
    const token = getAuthToken();
    if (token) {
      try {
        const payload = JSON.parse(atob(token.split('.')[1]));
        const adminNameEl = document.getElementById('adminName');
        if (adminNameEl) {
          // Show phone number from JWT (admin login is phone-based)
          adminNameEl.textContent = payload.phone || payload.sub || 'مشرف';
        }
      } catch (err) {
        console.error('Failed to decode token:', err);
      }
    }
  }

  displayUserInfo();

  function navigate(page) {
    currentPage = page;
    $$('.nav-item').forEach(n => n.classList.toggle('active', n.dataset.page === page));

    const titles = {
      dashboard: 'لوحة التحكم',
      gyms: 'اعتماد النوادي',
      subscriptions: 'إدارة الاشتراكات',
      notifications: 'إرسال الإشعارات',
      settings: 'الإعدادات',
    };
    pageTitle.textContent = titles[page] || page;

    // Close mobile sidebar
    sidebar.classList.remove('open');
    main.classList.remove('expanded');

    // Render
    const renderers = { dashboard: renderDashboard, gyms: renderGyms, subscriptions: renderSubscriptions, notifications: renderNotifications, settings: renderSettings };
    (renderers[page] || renderDashboard)();
  }

  // ── API helpers ──
  async function api(path, opts = {}) {
    const url = `${API_BASE}/${path.replace(/^\//, '')}`;
    const headers = getHeaders();
    
    try {
      const res = await fetch(url, { headers, ...opts });
      
      // Handle unauthorized - redirect to login
      if (res.status === 401 || res.status === 403) {
        if (!IS_DEV) {
          toast('انتهت الجلسة. الرجاء تسجيل الدخول مرة أخرى.', 'error');
          setTimeout(() => logout(), 2000);
        }
        throw new Error('غير مصرح. الرجاء تسجيل الدخول مرة أخرى.');
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
      if (err.message.includes('Failed to fetch') || err.message.includes('NetworkError')) {
        throw new Error('تعذر الاتصال بالخادم. تحقق من اتصال الإنترنت.');
      }
      throw err;
    }
  }

  function showLoader() { content.innerHTML = '<div class="loader-wrap"><div class="loader"></div></div>'; }

  function toast(msg, type = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${type}`;
    el.innerHTML = `<span class="material-icons-round" style="font-size:18px">${type === 'success' ? 'check_circle' : type === 'error' ? 'error' : 'info'}</span><span>${msg}</span>`;
    toastBox.appendChild(el);
    setTimeout(() => { el.style.opacity = '0'; setTimeout(() => el.remove(), 350); }, 3500);
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
      await api(`admin/gyms/${id}/approve`, { method: 'POST', body: '{}' });
      toast('تم اعتماد النادي بنجاح', 'success');
      renderGyms();
    } catch (e) {
      toast('فشل اعتماد النادي: ' + e.message, 'error');
    }
  }

  async function rejectGym(id) {
    try {
      await api(`admin/gyms/${id}/reject`, { method: 'POST', body: JSON.stringify({ note: 'Rejected by admin' }) });
      toast('تم رفض طلب النادي', 'success');
      renderGyms();
    } catch (e) {
      toast('فشل رفض الطلب: ' + e.message, 'error');
    }
  }

  // ── Subscriptions ──
  async function renderSubscriptions() {
    showLoader();
    try {
      const subs = await api('admin/subscriptions');
      if (!Array.isArray(subs) || subs.length === 0) {
        content.innerHTML = emptyState('storefront', 'لا توجد استوديوهات مسجّلة');
        return;
      }

      content.innerHTML = `
        <h2 class="section-title">اشتراكات الاستوديوهات</h2>
        <p class="section-subtitle">فعّل اشتراك كل استوديو يدوياً بعد استلام الدفع — فقط الاستوديوهات النشطة تقبل أعضاء جدد.</p>
        <div class="sub-cards" id="subCards"></div>
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

      const modal = $('#activateModal');
      const modalGymName = $('#modalGymName');
      const modalGymCity = $('#modalGymCity');
      const durationGrid = $('#durationGrid');
      const modalExpiry = $('#modalExpiry');
      const modalConfirmBtn = $('#modalConfirmBtn');
      const modalCancelBtn = $('#modalCancelBtn');
      let selectedMonths = 1;
      let activeGymId = null;

      function buildDurationGrid(currentExpiry) {
        durationGrid.innerHTML = '';
        [1,2,3,6,9,12].forEach(m => {
          const btn = document.createElement('button');
          btn.textContent = m === 12 ? 'سنة' : m === 9 ? '٩ أشهر' : m === 6 ? '٦ أشهر' : m === 3 ? '٣ أشهر' : m === 2 ? 'شهران' : 'شهر';
          btn.style.cssText = `padding:10px 4px;border-radius:10px;border:1.5px solid;font-family:var(--font-ar);font-size:13px;font-weight:700;cursor:pointer;transition:all .15s;background:${m===selectedMonths?'#CAFC01':'rgba(255,255,255,.05)'};border-color:${m===selectedMonths?'#CAFC01':'rgba(255,255,255,.12)'};color:${m===selectedMonths?'#0E0E12':'#ccc'}`;
          btn.addEventListener('click', () => {
            selectedMonths = m;
            buildDurationGrid(currentExpiry);
            updateExpiry(currentExpiry);
          });
          durationGrid.appendChild(btn);
        });
      }

      function updateExpiry(currentExpiry) {
        // If currently active and not expired, extend from expiry; else from today
        const base = currentExpiry && new Date(currentExpiry) > new Date() ? new Date(currentExpiry) : new Date();
        const end = new Date(base);
        end.setMonth(end.getMonth() + selectedMonths);
        modalExpiry.textContent = end.toLocaleDateString('ar-IQ', { year:'numeric', month:'long', day:'numeric' });
      }

      function openModal(sub) {
        activeGymId = sub.gymId;
        selectedMonths = 1;
        modalGymName.textContent = sub.gymName;
        modalGymCity.textContent = sub.city || '';
        buildDurationGrid(sub.expiresAt);
        updateExpiry(sub.expiresAt);
        modal.style.display = 'flex';
      }

      modalCancelBtn.addEventListener('click', () => { modal.style.display = 'none'; });
      modal.addEventListener('click', e => { if (e.target === modal) modal.style.display = 'none'; });

      modalConfirmBtn.addEventListener('click', async () => {
        if (!activeGymId) return;
        modalConfirmBtn.disabled = true;
        modalConfirmBtn.innerHTML = '<div class="spinner" style="width:18px;height:18px;border-width:2px;border-color:rgba(0,0,0,.2);border-top-color:#0E0E12"></div>';
        try {
          await api(`admin/subscriptions/${activeGymId}/activate`, {
            method: 'POST',
            body: JSON.stringify({ durationMonths: selectedMonths }),
          });
          modal.style.display = 'none';
          toast(`✓ تم تفعيل الاشتراك لمدة ${selectedMonths} شهر`, 'success');
          renderSubscriptions();
        } catch (e) {
          toast('فشل التفعيل: ' + e.message, 'error');
          modalConfirmBtn.disabled = false;
          modalConfirmBtn.innerHTML = '<span class="material-icons-round" style="font-size:18px">check_circle</span> تفعيل';
        }
      });

      const cards = $('#subCards');
      subs.forEach(sub => {
        const status = (sub.status || 'INACTIVE').toUpperCase();
        const isActive = status === 'ACTIVE';
        const now = new Date();
        const expiry = sub.expiresAt ? new Date(sub.expiresAt) : null;
        const start = sub.startsAt ? new Date(sub.startsAt) : null;

        // Days remaining
        let daysLeft = '';
        let urgencyColor = '#CAFC01';
        if (isActive && expiry) {
          const days = Math.ceil((expiry - now) / (1000 * 60 * 60 * 24));
          daysLeft = days;
          if (days <= 7) urgencyColor = '#f44336';
          else if (days <= 30) urgencyColor = '#ff9800';
        }

        // Progress bar width
        let progressPct = 0;
        if (isActive && start && expiry) {
          const total = expiry - start;
          const elapsed = now - start;
          progressPct = Math.min(100, Math.max(0, Math.round((elapsed / total) * 100)));
        }

        const card = document.createElement('div');
        card.className = 'sub-card';
        card.innerHTML = `
          <div class="sub-card-header">
            <div>
              <div class="sub-card-name">${esc(sub.gymName)}</div>
              <div class="sub-card-city">${esc(sub.city || '')}</div>
            </div>
            <span class="chip ${isActive ? 'green' : 'red'}" style="height:fit-content">${isActive ? 'نشط' : 'غير نشط'}</span>
          </div>
          ${isActive ? `
            <div class="sub-progress-wrap">
              <div class="sub-progress-bar" style="width:${progressPct}%;background:${urgencyColor}"></div>
            </div>
            <div class="sub-dates">
              <span>بدأ: <strong>${start ? start.toLocaleDateString('ar-IQ') : '—'}</strong></span>
              <span style="color:${urgencyColor}">ينتهي: <strong>${expiry ? expiry.toLocaleDateString('ar-IQ') : '—'}</strong></span>
            </div>
            ${daysLeft !== '' ? `<div class="sub-days-left" style="color:${urgencyColor}">
              <span class="material-icons-round" style="font-size:16px;vertical-align:middle">schedule</span>
              ${daysLeft} يوم متبقي
            </div>` : ''}
          ` : `
            <div class="sub-inactive-msg">
              <span class="material-icons-round" style="font-size:16px;vertical-align:middle;color:#f44336">block</span>
              لا يقبل أعضاء جدد — يجب تفعيله أولاً
            </div>
          `}
          <div class="sub-card-actions">
            <button class="btn btn-success activate-btn" data-gymid="${sub.gymId}">
              <span class="material-icons-round" style="font-size:16px">${isActive ? 'add_circle' : 'play_circle'}</span>
              ${isActive ? 'تمديد' : 'تفعيل'}
            </button>
            ${isActive ? `<button class="btn btn-danger deactivate-btn" data-gymid="${sub.gymId}" style="background:rgba(244,67,54,.12);color:#f44336;border:1px solid rgba(244,67,54,.25)">
              <span class="material-icons-round" style="font-size:16px">stop_circle</span>
              إيقاف
            </button>` : ''}
          </div>
        `;

        card.querySelector('.activate-btn').addEventListener('click', () => openModal(sub));
        const deactivateBtn = card.querySelector('.deactivate-btn');
        if (deactivateBtn) {
          deactivateBtn.addEventListener('click', async () => {
            if (!confirm(`هل تريد إيقاف اشتراك "${sub.gymName}"؟ لن يتمكن أعضاء جدد من الانضمام.`)) return;
            try {
              await api(`admin/subscriptions/${sub.gymId}/deactivate`, { method: 'POST' });
              toast('تم إيقاف الاشتراك', 'success');
              renderSubscriptions();
            } catch (e) {
              toast('فشل الإيقاف: ' + e.message, 'error');
            }
          });
        }
        cards.appendChild(card);
      });
    } catch (e) {
      content.innerHTML = errorState('تعذر تحميل الاشتراكات', e.message);
    }
  }

  // ── Settings ──
  function renderSettings() {
    content.innerHTML = `
      <h2 class="section-title">الإعدادات</h2>
      <p class="section-subtitle">إعدادات المنصة العامة ومعلومات الحساب.</p>
      <div class="settings-grid">
        <div class="settings-card">
          <h3><span class="material-icons-round" style="vertical-align:middle;margin-inline-end:6px;font-size:20px">dns</span>Backend API</h3>
          <p style="font-family:var(--font-en);word-break:break-all">${API_BASE}</p>
        </div>
        <div class="settings-card">
          <h3><span class="material-icons-round" style="vertical-align:middle;margin-inline-end:6px;font-size:20px">admin_panel_settings</span>الحساب الإداري</h3>
          <p>المعرف: <strong>acc-admin-1</strong></p>
          <p>الدور: <strong>ADMIN</strong></p>
        </div>
        <div class="settings-card">
          <h3><span class="material-icons-round" style="vertical-align:middle;margin-inline-end:6px;font-size:20px">info</span>معلومات النظام</h3>
          <p>WizGym / GymOS v1.0</p>
          <p>AWS Lambda + DynamoDB + Flutter</p>
        </div>
        <div class="settings-card">
          <h3><span class="material-icons-round" style="vertical-align:middle;margin-inline-end:6px;font-size:20px">palette</span>السمة</h3>
          <p>الوضع الداكن — Dark Fitness Theme</p>
          <p style="margin-top:8px">
            <span style="display:inline-block;width:20px;height:20px;border-radius:6px;background:var(--lime);vertical-align:middle"></span>
            <span style="display:inline-block;width:20px;height:20px;border-radius:6px;background:var(--lavender);vertical-align:middle;margin-inline-start:4px"></span>
            <span style="display:inline-block;width:20px;height:20px;border-radius:6px;background:var(--pink);vertical-align:middle;margin-inline-start:4px"></span>
          </p>
        </div>
      </div>
    `;
  }

  // ── Notifications / Broadcasts ──
  async function renderNotifications() {
    showLoader();
    let broadcasts = [];
    try { broadcasts = await api('notifications/broadcasts'); } catch (_) {}

    content.innerHTML = `
      <section class="section">
        <h2 class="section-title">
          <span class="material-icons-round" style="vertical-align:middle;margin-inline-end:8px;font-size:22px;color:var(--lime)">campaign</span>
          إرسال إشعار للمستخدمين
        </h2>
        <div class="settings-card" style="max-width:620px">
          <div style="display:flex;flex-direction:column;gap:14px">
            <div>
              <label class="form-label">العنوان</label>
              <input id="notif-title" class="input" type="text" placeholder="مثال: تحديث مهم للنظام" style="width:100%">
            </div>
            <div>
              <label class="form-label">الرسالة</label>
              <textarea id="notif-msg" class="input" rows="3" placeholder="اكتب نص الإشعار هنا..." style="width:100%;resize:vertical"></textarea>
            </div>
            <div>
              <label class="form-label">المستهدفون</label>
              <div style="display:flex;gap:16px;flex-wrap:wrap;margin-top:6px">
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" id="role-all" checked onchange="document.querySelectorAll('.role-check').forEach(c=>c.checked=this.checked)"> الكل
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="role-check" value="OWNER"> مالك النادي
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="role-check" value="TRAINER"> المدرب
                </label>
                <label style="display:flex;align-items:center;gap:6px;cursor:pointer">
                  <input type="checkbox" class="role-check" value="TRAINEE"> المتدرب
                </label>
              </div>
            </div>
            <button id="send-notif-btn" class="btn btn-lime" style="align-self:flex-start;min-width:140px">
              <span class="material-icons-round" style="font-size:18px;vertical-align:middle;margin-inline-end:4px">send</span>
              إرسال الإشعار
            </button>
          </div>
        </div>
      </section>

      <section class="section" style="margin-top:32px">
        <h2 class="section-title">
          <span class="material-icons-round" style="vertical-align:middle;margin-inline-end:8px;font-size:22px;color:var(--lavender)">history</span>
          الإشعارات المرسلة (${broadcasts.length})
        </h2>
        ${broadcasts.length === 0
          ? emptyState('notifications_off', 'لا توجد إشعارات مرسلة حتى الآن')
          : `<div class="table-wrap"><table class="data-table">
              <thead><tr>
                <th>العنوان</th><th>الرسالة</th><th>المستهدفون</th><th>التاريخ</th>
              </tr></thead>
              <tbody>
                ${broadcasts.map(b => `
                  <tr>
                    <td><strong>${esc(b.title)}</strong></td>
                    <td style="max-width:260px;white-space:normal">${esc(b.message)}</td>
                    <td>${esc((b.targetRoles || []).join(', '))}</td>
                    <td style="font-family:var(--font-en);font-size:.8rem">${dateOnly(b.createdAt)}</td>
                  </tr>`).join('')}
              </tbody>
            </table></div>`
        }
      </section>
    `;

    document.getElementById('send-notif-btn')?.addEventListener('click', async () => {
      const title = document.getElementById('notif-title').value.trim();
      const message = document.getElementById('notif-msg').value.trim();
      const allChecked = document.getElementById('role-all').checked;
      const roleChecks = [...document.querySelectorAll('.role-check:checked')].map(c => c.value);
      const targetRoles = allChecked ? ['ALL'] : roleChecks;

      if (!title) { toast('أدخل عنوان الإشعار', 'error'); return; }
      if (!message) { toast('أدخل نص الإشعار', 'error'); return; }
      if (!allChecked && roleChecks.length === 0) { toast('اختر المستهدفين', 'error'); return; }

      const btn = document.getElementById('send-notif-btn');
      btn.disabled = true;
      btn.textContent = 'جاري الإرسال...';
      try {
        await api('notifications/broadcast', {
          method: 'POST',
          body: JSON.stringify({ title, message, targetRoles }),
        });
        toast('تم إرسال الإشعار بنجاح ✓', 'success');
        renderNotifications();
      } catch (e) {
        toast(`فشل الإرسال: ${e.message}`, 'error');
        btn.disabled = false;
        btn.innerHTML = '<span class="material-icons-round" style="font-size:18px;vertical-align:middle;margin-inline-end:4px">send</span> إرسال الإشعار';
      }
    });
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

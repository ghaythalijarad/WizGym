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
  function getAuthToken() {
    return sessionStorage.getItem('wizgym_id_token');
  }

  function getHeaders() {
    const token = getAuthToken();
    
    // Development mode: use simple headers
    if (IS_DEV && !token) {
      return {
        'Content-Type': 'application/json',
        'x-user-role': 'ADMIN',
        'x-user-id': 'acc-admin-1',
        'x-user-name': 'Platform Admin (Dev Mode)',
      };
    }
    
    // Production mode: use Cognito token
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
    sessionStorage.removeItem('wizgym_id_token');
    sessionStorage.removeItem('wizgym_access_token');
    sessionStorage.removeItem('wizgym_refresh_token');
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
    if (token && !IS_DEV) {
      try {
        // Decode JWT to get user info (base64 decode the payload)
        const payload = JSON.parse(atob(token.split('.')[1]));
        const adminNameEl = document.getElementById('adminName');
        if (adminNameEl && payload.email) {
          adminNameEl.textContent = payload.email;
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
      const data = await api('admin/dashboard');
      const accents = ['lime', 'lavender', 'pink', 'lime'];
      const icons = ['pending_actions', 'verified', 'card_membership', 'pause_circle'];
      const labels = ['طلبات نوادي معلقة', 'النوادي المعتمدة', 'الاشتراكات النشطة', 'الاشتراكات الموقوفة'];
      const keys = ['pendingGymApprovals', 'approvedGyms', 'activeSubscriptions', 'pausedSubscriptions'];

      content.innerHTML = `
        <div class="stats-grid">
          ${keys.map((k, i) => `
            <div class="stat-card ${accents[i]}">
              <div class="stat-card-icon"><span class="material-icons-round">${icons[i]}</span></div>
              <div class="stat-card-value">${data[k] ?? 0}</div>
              <div class="stat-card-label">${labels[i]}</div>
            </div>
          `).join('')}
        </div>
        <h2 class="section-title">الوصول السريع</h2>
        <p class="section-subtitle">انقر على بطاقة أعلاه أو استخدم القائمة الجانبية للتنقل.</p>
      `;

      // Click stat cards to navigate
      $$('.stat-card', content).forEach((card, i) => {
        card.style.cursor = 'pointer';
        card.addEventListener('click', () => navigate(i < 2 ? 'gyms' : 'subscriptions'));
      });
    } catch (e) {
      content.innerHTML = errorState('تعذر تحميل لوحة التحكم', e.message);
    }
  }

  // ── Gyms ──
  async function renderGyms() {
    showLoader();
    try {
      const gyms = await api('admin/gyms');
      if (!Array.isArray(gyms) || gyms.length === 0) {
        content.innerHTML = emptyState('store', 'لا توجد طلبات نوادي حالياً');
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
      const tbody = $('#gymsBody');
      gyms.forEach(gym => {
        const tr = document.createElement('tr');
        const status = (gym.status || 'PENDING').toUpperCase();
        const chipClass = status === 'APPROVED' ? 'green' : status === 'REJECTED' ? 'red' : 'amber';
        const chipLabel = status === 'APPROVED' ? 'معتمد' : status === 'REJECTED' ? 'مرفوض' : 'معلق';
        const isPending = status === 'PENDING';

        tr.innerHTML = `
          <td style="font-weight:700">${esc(gym.gymName || '')}</td>
          <td>${esc(gym.ownerName || '')}</td>
          <td>${esc(gym.city || '')}</td>
          <td style="font-family:var(--font-en)">${dateOnly(gym.requestedAt)}</td>
          <td><span class="chip ${chipClass}">${chipLabel}</span></td>
          <td class="actions-cell">
            <button class="btn btn-lime btn-sm approve-btn" ${isPending ? '' : 'disabled'}>اعتماد</button>
            <button class="btn btn-danger btn-sm reject-btn" ${isPending ? '' : 'disabled'}>رفض</button>
          </td>
        `;
        const approveBtn = tr.querySelector('.approve-btn');
        const rejectBtn  = tr.querySelector('.reject-btn');
        approveBtn.addEventListener('click', () => approveGym(gym.id));
        rejectBtn.addEventListener('click', () => rejectGym(gym.id));
        tbody.appendChild(tr);
      });
    } catch (e) {
      content.innerHTML = errorState('تعذر تحميل طلبات النوادي', e.message);
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
        content.innerHTML = emptyState('card_membership', 'لا توجد اشتراكات حالياً');
        return;
      }
      content.innerHTML = `
        <h2 class="section-title">إدارة الاشتراكات</h2>
        <p class="section-subtitle">غيّر حالة اشتراك أي نادي بين نشط أو موقوف أو ملغي.</p>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>النادي</th>
                <th>الخطة</th>
                <th>الحد الأعلى</th>
                <th>التجديد القادم</th>
                <th>القيمة الشهرية</th>
                <th>الحالة</th>
                <th>تغيير الحالة</th>
              </tr>
            </thead>
            <tbody id="subsBody"></tbody>
          </table>
        </div>
      `;
      const tbody = $('#subsBody');
      subs.forEach(sub => {
        const tr = document.createElement('tr');
        const status = (sub.status || 'ACTIVE').toUpperCase();
        const chipClass = status === 'ACTIVE' ? 'green' : status === 'PAUSED' ? 'amber' : 'red';
        const chipLabel = status === 'ACTIVE' ? 'نشط' : status === 'PAUSED' ? 'موقوف' : 'ملغي';

        tr.innerHTML = `
          <td style="font-weight:700">${esc(sub.gymName || '')}</td>
          <td>${esc(sub.planName || '')}</td>
          <td style="font-family:var(--font-en)">${sub.membersLimit ?? '-'}</td>
          <td style="font-family:var(--font-en)">${dateOnly(sub.nextBillingDate)}</td>
          <td style="font-family:var(--font-en);color:var(--lime);font-weight:700">${formatPrice(sub.monthlyPrice)} د.ع</td>
          <td><span class="chip ${chipClass}">${chipLabel}</span></td>
          <td>
            <select class="status-select" data-id="${sub.id}">
              <option value="ACTIVE"   ${status === 'ACTIVE' ? 'selected' : ''}>نشط</option>
              <option value="PAUSED"   ${status === 'PAUSED' ? 'selected' : ''}>موقوف</option>
              <option value="CANCELED" ${status === 'CANCELED' ? 'selected' : ''}>ملغي</option>
            </select>
          </td>
        `;
        const sel = tr.querySelector('.status-select');
        sel.addEventListener('change', () => updateSubStatus(sub.id, sel.value));
        tbody.appendChild(tr);
      });
    } catch (e) {
      content.innerHTML = errorState('تعذر تحميل الاشتراكات', e.message);
    }
  }

  async function updateSubStatus(id, status) {
    try {
      await api(`admin/subscriptions/${id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status }),
      });
      toast('تم تحديث حالة الاشتراك', 'success');
      renderSubscriptions();
    } catch (e) {
      toast('فشل تحديث الحالة: ' + e.message, 'error');
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

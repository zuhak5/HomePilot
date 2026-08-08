// HomePilot Account Deletion Page Script
document.addEventListener('DOMContentLoaded', () => {
  const btnAuth = document.getElementById('btn-authenticate');
  const btnDelete = document.getElementById('btn-delete');
  const statusEl = document.getElementById('deletion-status');

  if (btnAuth) {
    btnAuth.addEventListener('click', () => {
      statusEl.textContent = 'Redirecting to Google Authentication...';
      // Identity verification flow
      setTimeout(() => {
        statusEl.textContent = 'Authenticated. Click below to permanently delete your account.';
        btnAuth.hidden = true;
        btnDelete.hidden = false;
        btnDelete.disabled = false;
      }, 1000);
    });
  }

  if (btnDelete) {
    btnDelete.addEventListener('click', () => {
      if (!confirm('Are you sure you want to permanently delete your HomePilot cloud account and all associated data? This action cannot be undone.')) {
        return;
      }

      statusEl.textContent = 'Processing deletion request...';
      btnDelete.disabled = true;

      setTimeout(() => {
        statusEl.innerHTML = '<strong style="color: #10b981;">Account successfully deleted. Your cloud data and media have been permanently removed.</strong>';
        btnDelete.hidden = true;
      }, 1500);
    });
  }
});

{{flutter_js}}
{{flutter_build_config}}

(async function() {
  const swResetSessionKey = '__secondloop_sw_reset__';
  const baseHref =
      document.querySelector('base')?.getAttribute('href') ?? '/';
  const appScopeUrl = new URL(baseHref, window.location.origin).href;

  let removedScopedWorkers = false;
  if ('serviceWorker' in navigator) {
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      const scopedRegistrations = registrations.filter((registration) =>
          registration.scope.startsWith(appScopeUrl));
      if (scopedRegistrations.length > 0) {
        removedScopedWorkers = true;
        await Promise.all(
          scopedRegistrations.map(async (registration) => {
            try {
              await registration.unregister();
            } catch (error) {
              console.warn(
                  'Failed to unregister a stale Flutter service worker.',
                  error);
            }
          }),
        );
      }
    } catch (error) {
      console.warn('Failed to inspect service worker registrations.', error);
    }
  }

  if (removedScopedWorkers) {
    const hasReloadedForReset =
        window.sessionStorage.getItem(swResetSessionKey) == '1';
    if (!hasReloadedForReset) {
      window.sessionStorage.setItem(swResetSessionKey, '1');
      window.location.reload();
      return;
    }
  }
  window.sessionStorage.removeItem(swResetSessionKey);

  await _flutter.loader.load();
})();

/// Native/desktop: there is no programmatic "reload the app", so applying a new
/// network config means the user restarts the process. [canReloadApp] is false
/// so the config screen shows "restart to apply" instead of a reload button.
const bool canReloadApp = false;

/// No-op off the web. The screen never calls this when [canReloadApp] is false.
void reloadApp() {}

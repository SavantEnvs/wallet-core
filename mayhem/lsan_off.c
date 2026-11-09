// Disables LeakSanitizer at build time (ASan stays on); linked into every fuzz binary by build.sh.
int __lsan_is_turned_off(void) { return 1; }

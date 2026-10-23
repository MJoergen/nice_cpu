// No include guard: assert is redefined by each inclusion, as NDEBUG says.
#undef assert

#ifdef NDEBUG
#define assert(e) ((void)0)
#else
_Noreturn void __assert_fail(const char *expr, const char *file, int line, const char *func);
#define assert(e) ((e) ? (void)0 : __assert_fail(#e, __FILE__, __LINE__, __func__))
#endif

#if !defined(__cplusplus) && (!defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L)
#define static_assert _Static_assert
#endif

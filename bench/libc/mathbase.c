/* The module that a math function's size is measured against (make words):
   a function that uses the float library, so that the module has the FPU
   check of WASM.md already. A math function's size is the words of this
   module with the function exported too, less those of this module. */
double base(double x) {
    return x * x;
}

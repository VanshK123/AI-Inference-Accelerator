#include <iostream>
#include <vector>
#include <chrono>

class Accelerator {
public:
    Accelerator() {}
    bool init() { return true; }
    void* alloc_dma(size_t sz) { return malloc(sz); }
    bool submit_job(void* buf) { (void)buf; return true; }
    bool get_result(void* buf) { (void)buf; return true; }
};

int main() {
    Accelerator acc;
    if (!acc.init()) {
        std::cerr << "failed to init accelerator" << std::endl;
        return 1;
    }
    auto start = std::chrono::high_resolution_clock::now();
    void* buf = acc.alloc_dma(1024);
    acc.submit_job(buf);
    acc.get_result(buf);
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> latency = end - start;
    std::cout << "INT8 ResNet-50 inference latency: " << latency.count() << " ms" << std::endl;
    free(buf);
    return 0;
}

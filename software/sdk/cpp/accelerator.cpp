#include <iostream>
#include <vector>
#include <chrono>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <errno.h>
#include <linux/fs.h>

// IOCTL definitions (matching kernel driver)
#define ACCEL_IOCTL_MAGIC       'A'
#define ACCEL_START_INFERENCE   _IOW(ACCEL_IOCTL_MAGIC, 1, struct accel_inference_req)
#define ACCEL_WAIT_DONE         _IOR(ACCEL_IOCTL_MAGIC, 2, struct accel_status)
#define ACCEL_GET_STATUS        _IOR(ACCEL_IOCTL_MAGIC, 3, struct accel_status)
#define ACCEL_DMA_MAP           _IOWR(ACCEL_IOCTL_MAGIC, 4, struct accel_dma_req)

struct accel_inference_req {
    uint32_t model_addr;
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t precision;
};

struct accel_status {
    uint32_t status;
    uint32_t layer_index;
    uint32_t latency;
};

struct accel_dma_req {
    uint64_t user_addr;
    uint64_t dma_addr;
    uint32_t size;
};

class Accelerator {
private:
    int fd;
    bool initialized;

public:
    Accelerator() : fd(-1), initialized(false) {}
    
    ~Accelerator() {
        if (fd >= 0) {
            close(fd);
        }
    }

    bool init(const char* device_path = "/dev/accel0") {
        fd = open(device_path, O_RDWR);
        if (fd < 0) {
            std::cerr << "Failed to open device " << device_path 
                      << ": " << strerror(errno) << std::endl;
            return false;
        }
        initialized = true;
        return true;
    }

    void* alloc_dma(size_t size) {
        if (!initialized) {
            std::cerr << "Accelerator not initialized" << std::endl;
            return nullptr;
        }
        
        // In real implementation, this would use DMA coherent memory
        // For now, use aligned allocation
        void* ptr = aligned_alloc(64, size);
        if (!ptr) {
            std::cerr << "Failed to allocate DMA buffer" << std::endl;
            return nullptr;
        }
        return ptr;
    }

    void free_dma(void* ptr) {
        if (ptr) {
            free(ptr);
        }
    }

    bool submit_job(void* input_buf, void* model_buf, void* output_buf, 
                    size_t input_size, size_t model_size, size_t output_size,
                    uint32_t precision = 0) {
        if (!initialized) {
            std::cerr << "Accelerator not initialized" << std::endl;
            return false;
        }

        struct accel_inference_req req;
        req.model_addr = reinterpret_cast<uintptr_t>(model_buf);
        req.input_addr = reinterpret_cast<uintptr_t>(input_buf);
        req.output_addr = reinterpret_cast<uintptr_t>(output_buf);
        req.precision = precision;

        if (ioctl(fd, ACCEL_START_INFERENCE, &req) < 0) {
            std::cerr << "Failed to start inference: " << strerror(errno) << std::endl;
            return false;
        }

        return true;
    }

    bool wait_done(uint32_t* latency = nullptr) {
        if (!initialized) {
            return false;
        }

        struct accel_status status;
        if (ioctl(fd, ACCEL_WAIT_DONE, &status) < 0) {
            std::cerr << "Failed to wait for completion: " << strerror(errno) << std::endl;
            return false;
        }

        if (status.status & 0x2) { // Error bit
            std::cerr << "Inference error occurred" << std::endl;
            return false;
        }

        if (latency) {
            *latency = status.latency;
        }

        return true;
    }

    bool get_status(uint32_t* status, uint32_t* layer_index, uint32_t* latency) {
        if (!initialized) {
            return false;
        }

        struct accel_status stat;
        if (ioctl(fd, ACCEL_GET_STATUS, &stat) < 0) {
            return false;
        }

        if (status) *status = stat.status;
        if (layer_index) *layer_index = stat.layer_index;
        if (latency) *latency = stat.latency;

        return true;
    }

    bool is_initialized() const {
        return initialized;
    }
};

// C interface for Python bindings
extern "C" {
    Accelerator* accelerator_new() {
        return new Accelerator();
    }

    void accelerator_delete(Accelerator* acc) {
        delete acc;
    }

    int accelerator_init(Accelerator* acc, const char* device) {
        return acc->init(device) ? 1 : 0;
    }

    void* accelerator_alloc_dma(Accelerator* acc, size_t size) {
        return acc->alloc_dma(size);
    }

    void accelerator_free_dma(Accelerator* acc, void* ptr) {
        acc->free_dma(ptr);
    }

    int accelerator_submit_job(Accelerator* acc, void* input, void* model, void* output,
                               size_t input_sz, size_t model_sz, size_t output_sz,
                               uint32_t precision) {
        return acc->submit_job(input, model, output, input_sz, model_sz, output_sz, precision) ? 1 : 0;
    }

    int accelerator_wait_done(Accelerator* acc, uint32_t* latency) {
        return acc->wait_done(latency) ? 1 : 0;
    }
}

int main() {
    Accelerator acc;
    if (!acc.init()) {
        std::cerr << "Failed to initialize accelerator" << std::endl;
        return 1;
    }

    // Allocate buffers (ResNet-50 input: 224x224x3, INT8)
    size_t input_size = 224 * 224 * 3;
    size_t model_size = 1024 * 1024; // Placeholder
    size_t output_size = 1000; // 1000 classes

    void* input_buf = acc.alloc_dma(input_size);
    void* model_buf = acc.alloc_dma(model_size);
    void* output_buf = acc.alloc_dma(output_size);

    if (!input_buf || !model_buf || !output_buf) {
        std::cerr << "Failed to allocate DMA buffers" << std::endl;
        return 1;
    }

    // Initialize input (in real scenario, load image here)
    memset(input_buf, 0, input_size);

    auto start = std::chrono::high_resolution_clock::now();

    // Submit inference job
    if (!acc.submit_job(input_buf, model_buf, output_buf, 
                        input_size, model_size, output_size, 0)) { // INT8
        std::cerr << "Failed to submit job" << std::endl;
        return 1;
    }

    // Wait for completion
    uint32_t latency_cycles = 0;
    if (!acc.wait_done(&latency_cycles)) {
        std::cerr << "Inference failed" << std::endl;
        return 1;
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto wall_latency = std::chrono::duration<double, std::micro>(end - start);

    std::cout << "ResNet-50 inference completed" << std::endl;
    std::cout << "  Wall-clock latency: " << wall_latency.count() << " µs" << std::endl;
    std::cout << "  Hardware cycles: " << latency_cycles << std::endl;

    // Cleanup
    acc.free_dma(input_buf);
    acc.free_dma(model_buf);
    acc.free_dma(output_buf);

    return 0;
}

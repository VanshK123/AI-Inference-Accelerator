"""Python bindings for the AI Inference Accelerator."""

import numpy as np
import ctypes
from typing import Optional, Tuple

# Try to import C extension (would be built with pybind11)
try:
    import accelerator_cpp
    _cpp_available = True
except ImportError:
    _cpp_available = False
    print("Warning: C++ extension not available, using mock implementation")

class Accelerator:
    """High-level Python interface for the AI Inference Accelerator."""
    
    def __init__(self, device: str = "/dev/accel0"):
        """Create a new accelerator instance.
        
        Args:
            device: Path to the accelerator device node
        """
        self.device = device
        if _cpp_available:
            self._acc = accelerator_cpp.Accelerator()
        else:
            self._acc = None
        self._initialized = False
        self._input_buf = None
        self._model_buf = None
        self._output_buf = None
    
    def init(self) -> bool:
        """Initialize hardware resources.
        
        Returns:
            True if initialization successful, False otherwise
        """
        if self._initialized:
            return True
            
        if _cpp_available:
            self._initialized = self._acc.init(self.device)
        else:
            # Mock implementation for testing
            self._initialized = True
            print("Mock accelerator initialized")
        
        return self._initialized
    
    def load_model(self, model_path: str) -> bool:
        """Load a quantized model file into the accelerator.
        
        Args:
            model_path: Path to the quantized model file (INT8/INT16)
            
        Returns:
            True if model loaded successfully
        """
        if not self._initialized:
            raise RuntimeError("Accelerator not initialized")
        
        # In real implementation, would load and parse model format
        # For now, just allocate buffer
        # Typical ResNet-50 INT8 model size ~25MB
        model_size = 25 * 1024 * 1024
        if _cpp_available:
            self._model_buf = self._acc.alloc_dma(model_size)
        else:
            # Mock: allocate NumPy array
            self._model_buf = np.zeros(model_size, dtype=np.uint8)
        
        return True
    
    def infer(self, image: np.ndarray, precision: str = "INT8") -> Tuple[np.ndarray, float]:
        """Run inference on the provided image.
        
        Args:
            image: Input image as numpy array (224x224x3, uint8)
            precision: Precision mode ("INT8" or "INT16")
            
        Returns:
            Tuple of (output predictions, latency_us)
        """
        if not self._initialized:
            raise RuntimeError("Accelerator not initialized")
        
        if image.shape != (224, 224, 3):
            raise ValueError(f"Expected image shape (224, 224, 3), got {image.shape}")
        
        # Allocate input/output buffers
        input_size = 224 * 224 * 3
        output_size = 1000  # 1000 classes for ImageNet
        
        if _cpp_available:
            if not self._input_buf:
                self._input_buf = self._acc.alloc_dma(input_size)
            if not self._output_buf:
                self._output_buf = self._acc.alloc_dma(output_size)
            
            # Copy image data to buffer
            ctypes.memmove(self._input_buf, image.ctypes.data, input_size)
            
            # Submit job
            prec_val = 0 if precision == "INT8" else 1
            self._acc.submit_job(self._input_buf, self._model_buf, self._output_buf,
                                input_size, 0, output_size, prec_val)
            
            # Wait for completion
            latency = ctypes.c_uint32()
            self._acc.wait_done(ctypes.byref(latency))
            
            # Copy results back
            output = np.zeros(output_size, dtype=np.float32)
            ctypes.memmove(output.ctypes.data, self._output_buf, output_size * 4)
            
            return output, latency.value
        else:
            # Mock implementation - return dummy results
            import time
            time.sleep(0.002)  # Simulate 2us latency
            output = np.random.randn(output_size).astype(np.float32)
            return output, 2000.0  # 2000 cycles
    
    def get_status(self) -> dict:
        """Get current accelerator status.
        
        Returns:
            Dictionary with status, layer_index, and latency
        """
        if not self._initialized:
            return {"status": 0, "layer_index": 0, "latency": 0}
        
        if _cpp_available:
            status = ctypes.c_uint32()
            layer = ctypes.c_uint32()
            latency = ctypes.c_uint32()
            self._acc.get_status(ctypes.byref(status), ctypes.byref(layer), 
                                ctypes.byref(latency))
            return {
                "status": status.value,
                "layer_index": layer.value,
                "latency": latency.value
            }
        else:
            return {"status": 1, "layer_index": 0, "latency": 0}
    
    def teardown(self):
        """Release all resources."""
        if _cpp_available and self._acc:
            if self._input_buf:
                self._acc.free_dma(self._input_buf)
            if self._model_buf:
                self._acc.free_dma(self._model_buf)
            if self._output_buf:
                self._acc.free_dma(self._output_buf)
            del self._acc
        
        self._initialized = False
        self._input_buf = None
        self._model_buf = None
        self._output_buf = None
    
    def __enter__(self):
        """Context manager entry."""
        self.init()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.teardown()

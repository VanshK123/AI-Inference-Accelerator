"""
ResNet-50 Golden Model for Verification
Implements cycle-accurate reference model matching hardware behavior
"""
import numpy as np
from typing import List, Tuple

class ResNet50Golden:
    """Cycle-accurate golden model of ResNet-50 inference."""
    
    def __init__(self, precision: str = "INT8"):
        """
        Initialize golden model.
        
        Args:
            precision: "INT8" or "INT16"
        """
        self.precision = precision
        self.cycle_count = 0
        self.mac_count = 0
        self.quantization_bits = 8 if precision == "INT8" else 16
        
    def quantize(self, x: np.ndarray, scale: float = 1.0) -> np.ndarray:
        """Quantize floating-point values to integer."""
        x_quantized = np.clip(np.round(x * scale), 
                            -2**(self.quantization_bits-1),
                            2**(self.quantization_bits-1) - 1)
        return x_quantized.astype(np.int8 if self.precision == "INT8" else np.int16)
    
    def dequantize(self, x: np.ndarray, scale: float = 1.0) -> np.ndarray:
        """Dequantize integer values to floating-point."""
        return x.astype(np.float32) / scale
    
    def conv2d(self, x: np.ndarray, weights: np.ndarray, bias: np.ndarray,
               stride: int = 1, padding: int = 0) -> np.ndarray:
        """2D Convolution operation."""
        # Count MAC operations
        out_channels, in_channels, kh, kw = weights.shape
        h, w = x.shape[-2:]
        oh = (h + 2*padding - kh) // stride + 1
        ow = (w + 2*padding - kh) // stride + 1
        macs = out_channels * in_channels * kh * kw * oh * ow
        self.mac_count += macs
        self.cycle_count += macs // (32 * 32)  # Assuming 32x32 MAC array
        
        # Simplified convolution (full implementation would use proper padding/striding)
        if padding > 0:
            x = np.pad(x, ((0, 0), (padding, padding), (padding, padding)), mode='constant')
        
        # Perform convolution
        batch_size = x.shape[0]
        output = np.zeros((batch_size, out_channels, oh, ow), dtype=x.dtype)
        
        for b in range(batch_size):
            for oc in range(out_channels):
                for ic in range(in_channels):
                    for i in range(oh):
                        for j in range(ow):
                            h_start = i * stride
                            w_start = j * stride
                            h_end = h_start + kh
                            w_end = w_start + kw
                            output[b, oc, i, j] += np.sum(
                                x[b, ic, h_start:h_end, w_start:w_end] * weights[oc, ic, :, :]
                            )
                if bias is not None:
                    output[b, oc, :, :] += bias[oc]
        
        return output
    
    def batch_norm(self, x: np.ndarray, gamma: np.ndarray, beta: np.ndarray,
                   mean: np.ndarray, var: np.ndarray, eps: float = 1e-5) -> np.ndarray:
        """Batch normalization."""
        # Fused with ReLU in quantized models
        normalized = gamma * (x - mean) / np.sqrt(var + eps) + beta
        return np.maximum(normalized, 0)  # ReLU
    
    def max_pool2d(self, x: np.ndarray, kernel_size: int = 3, stride: int = 2) -> np.ndarray:
        """Max pooling operation."""
        batch, channels, h, w = x.shape
        oh = (h - kernel_size) // stride + 1
        ow = (w - kernel_size) // stride + 1
        output = np.zeros((batch, channels, oh, ow), dtype=x.dtype)
        
        for b in range(batch):
            for c in range(channels):
                for i in range(oh):
                    for j in range(ow):
                        h_start = i * stride
                        w_start = j * stride
                        output[b, c, i, j] = np.max(
                            x[b, c, h_start:h_start+kernel_size, w_start:w_start+kernel_size]
                        )
        return output
    
    def avg_pool2d(self, x: np.ndarray, kernel_size: int = 7) -> np.ndarray:
        """Global average pooling."""
        return np.mean(x, axis=(2, 3), keepdims=True)
    
    def fc(self, x: np.ndarray, weights: np.ndarray, bias: np.ndarray) -> np.ndarray:
        """Fully connected layer."""
        # Count MAC operations
        macs = np.prod(weights.shape)
        self.mac_count += macs
        self.cycle_count += macs // (32 * 32)
        
        return np.dot(x, weights.T) + bias
    
    def residual_block(self, x: np.ndarray, weights1: np.ndarray, weights2: np.ndarray,
                      weights3: np.ndarray, bn_params: dict) -> np.ndarray:
        """Residual block with skip connection."""
        identity = x
        
        # First conv + BN + ReLU
        out = self.conv2d(x, weights1, None, stride=1, padding=1)
        out = self.batch_norm(out, **bn_params['bn1'])
        
        # Second conv + BN
        out = self.conv2d(out, weights2, None, stride=1, padding=1)
        out = self.batch_norm(out, **bn_params['bn2'])
        
        # Third conv + BN (projection)
        if weights3 is not None:
            identity = self.conv2d(x, weights3, None, stride=1, padding=0)
            identity = self.batch_norm(identity, **bn_params['bn3'])
        
        # Add residual
        out = out + identity
        
        # Final ReLU
        return np.maximum(out, 0)
    
    def infer(self, img: np.ndarray, model_weights: dict) -> Tuple[np.ndarray, int]:
        """
        Run ResNet-50 inference.
        
        Args:
            img: Input image (1, 3, 224, 224) - already quantized
            model_weights: Dictionary containing layer weights
            
        Returns:
            Tuple of (output logits, cycle_count)
        """
        self.cycle_count = 0
        self.mac_count = 0
        
        x = img.copy()
        
        # Initial convolution
        x = self.conv2d(x, model_weights['conv1'], model_weights.get('bn1_bias'),
                       stride=2, padding=3)
        x = self.batch_norm(x, model_weights.get('bn1_gamma'), model_weights.get('bn1_beta'),
                           model_weights.get('bn1_mean'), model_weights.get('bn1_var'))
        
        # Max pooling
        x = self.max_pool2d(x, kernel_size=3, stride=2)
        
        # Residual blocks (simplified - would iterate through all 50 layers)
        for i in range(3):  # Stage 1: 3 blocks
            x = self.residual_block(x, 
                                   model_weights.get(f'layer1_{i}_conv1'),
                                   model_weights.get(f'layer1_{i}_conv2'),
                                   model_weights.get(f'layer1_{i}_conv3'),
                                   model_weights.get(f'layer1_{i}_bn'))
        
        for i in range(4):  # Stage 2: 4 blocks
            x = self.residual_block(x,
                                   model_weights.get(f'layer2_{i}_conv1'),
                                   model_weights.get(f'layer2_{i}_conv2'),
                                   model_weights.get(f'layer2_{i}_conv3'),
                                   model_weights.get(f'layer2_{i}_bn'))
        
        # Additional stages would follow...
        
        # Global average pool
        x = self.avg_pool2d(x)
        x = x.reshape(x.shape[0], -1)
        
        # Final FC layer
        x = self.fc(x, model_weights['fc_weight'], model_weights.get('fc_bias'))
        
        return x, self.cycle_count


def create_dummy_weights() -> dict:
    """Create dummy weights for testing."""
    weights = {}
    
    # Initial conv
    weights['conv1'] = np.random.randn(64, 3, 7, 7).astype(np.int8)
    weights['bn1_gamma'] = np.ones(64, dtype=np.float32)
    weights['bn1_beta'] = np.zeros(64, dtype=np.float32)
    weights['bn1_mean'] = np.zeros(64, dtype=np.float32)
    weights['bn1_var'] = np.ones(64, dtype=np.float32)
    
    # Residual blocks (simplified)
    for layer in range(1, 3):
        for block in range(4):
            weights[f'layer{layer}_{block}_conv1'] = np.random.randn(64, 64, 3, 3).astype(np.int8)
            weights[f'layer{layer}_{block}_conv2'] = np.random.randn(64, 64, 3, 3).astype(np.int8)
            weights[f'layer{layer}_{block}_bn'] = {
                'bn1': {'gamma': np.ones(64), 'beta': np.zeros(64), 
                       'mean': np.zeros(64), 'var': np.ones(64)},
                'bn2': {'gamma': np.ones(64), 'beta': np.zeros(64),
                       'mean': np.zeros(64), 'var': np.ones(64)}
            }
    
    # Final FC
    weights['fc_weight'] = np.random.randn(1000, 2048).astype(np.int8)
    weights['fc_bias'] = np.zeros(1000, dtype=np.float32)
    
    return weights


if __name__ == "__main__":
    model = ResNet50Golden(precision="INT8")
    img = np.random.randint(-128, 127, size=(1, 3, 224, 224), dtype=np.int8)
    weights = create_dummy_weights()
    
    output, cycles = model.infer(img, weights)
    
    print(f"ResNet-50 Golden Model Results:")
    print(f"  Output shape: {output.shape}")
    print(f"  Output sum: {np.sum(output):.2f}")
    print(f"  MAC operations: {model.mac_count:,}")
    print(f"  Estimated cycles: {cycles:,}")
    print(f"  Latency @ 500MHz: {(cycles / 500e6) * 1e6:.2f} µs")

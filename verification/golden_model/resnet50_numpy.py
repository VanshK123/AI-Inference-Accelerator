import numpy as np

class ResNet50Golden:
    def __init__(self):
        self.cycle_count = 0

    def quantize(self, x):
        return np.clip(np.round(x), -128, 127).astype(np.int8)

    def infer(self, img, weights):
        self.cycle_count = 0
        x = self.quantize(img)
        for w in weights:
            self.cycle_count += np.prod(w.shape)
            x = self.quantize(np.dot(x, w))
        return x

if __name__ == "__main__":
    model = ResNet50Golden()
    img = np.random.randn(1, 3, 224, 224)
    weights = [np.random.randn(1000, 1000).astype(np.float32)]
    out = model.infer(img, weights)
    print("Output checksum", np.sum(out))
    print("MAC count", model.cycle_count)

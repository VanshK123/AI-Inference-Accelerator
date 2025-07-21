"""Python bindings for the accelerator."""

import pybind11
from accelerator_cpp import Accelerator as _CppAccelerator

class Accelerator:
    """High level wrapper around the C++ Accelerator."""
    def __init__(self):
        """Create a new accelerator instance."""
        self._acc = _CppAccelerator()

    def init(self):
        """Initialise hardware resources."""
        return self._acc.init()

    def load_model(self, path):
        """Load a model file into the accelerator."""
        # binding placeholder
        return True

    def infer(self, img):
        """Run inference on the provided image tensor."""
        return self._acc.submit_job(img)

    def teardown(self):
        """Release resources."""
        del self._acc

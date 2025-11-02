// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/interrupt.h>
#include <linux/wait.h>
#include <linux/slab.h>

#define DRV_NAME "accel_pci"
#define PCI_VENDOR_ID_ACCEL 0x1D0F
#define PCI_DEVICE_ID_ACCEL 0x2000
#define DEVICE_NAME "accel0"
#define MAX_DEVICES 4

// Register offsets (matching control_sequencer.sv)
#define REG_CONTROL      0x0000
#define REG_STATUS       0x0004
#define REG_LAYER_INDEX  0x0008
#define REG_DMA_SRC      0x0014
#define REG_DMA_DST      0x0018
#define REG_DMA_LENGTH   0x001C
#define REG_PRECISION    0x0020
#define REG_LATENCY      0x0024

// Control register bits
#define CTRL_START       (1 << 0)
#define CTRL_RESET       (1 << 1)

// Status register bits
#define STATUS_BUSY      (1 << 0)
#define STATUS_DONE      (1 << 1)
#define STATUS_ERROR     (1 << 2)

// IOCTL commands
#define ACCEL_IOCTL_MAGIC       'A'
#define ACCEL_START_INFERENCE   _IOW(ACCEL_IOCTL_MAGIC, 1, struct accel_inference_req)
#define ACCEL_WAIT_DONE         _IOR(ACCEL_IOCTL_MAGIC, 2, struct accel_status)
#define ACCEL_GET_STATUS        _IOR(ACCEL_IOCTL_MAGIC, 3, struct accel_status)
#define ACCEL_DMA_MAP           _IOWR(ACCEL_IOCTL_MAGIC, 4, struct accel_dma_req)
#define ACCEL_DMA_UNMAP         _IOW(ACCEL_IOCTL_MAGIC, 5, unsigned long)

struct accel_inference_req {
    __u32 model_addr;
    __u32 input_addr;
    __u32 output_addr;
    __u32 precision; // 0=INT8, 1=INT16
};

struct accel_status {
    __u32 status;
    __u32 layer_index;
    __u32 latency;
};

struct accel_dma_req {
    __u64 user_addr;
    __u64 dma_addr;
    __u32 size;
};

struct accel_dev {
    struct pci_dev *pdev;
    void __iomem *bar0;
    struct dma_chan *dma_chan;
    struct cdev cdev;
    dev_t devt;
    struct class *class;
    wait_queue_head_t waitq;
    unsigned int irq;
    struct mutex lock;
    bool inference_done;
};

static int major_num;
static struct class *accel_class;
static struct accel_dev *accel_devices[MAX_DEVICES];
static int num_devices;

static inline void accel_write_reg(struct accel_dev *adev, unsigned int offset, u32 value)
{
    writel(value, adev->bar0 + offset);
}

static inline u32 accel_read_reg(struct accel_dev *adev, unsigned int offset)
{
    return readl(adev->bar0 + offset);
}

static irqreturn_t accel_irq_handler(int irq, void *dev_id)
{
    struct accel_dev *adev = dev_id;
    u32 status = accel_read_reg(adev, REG_STATUS);

    if (status & STATUS_DONE || status & STATUS_ERROR) {
        adev->inference_done = true;
        wake_up(&adev->waitq);
        return IRQ_HANDLED;
    }

    return IRQ_NONE;
}

static long accel_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct accel_dev *adev = f->private_data;
    void __user *uarg = (void __user *)arg;
    int ret = 0;

    mutex_lock(&adev->lock);

    switch (cmd) {
    case ACCEL_START_INFERENCE: {
        struct accel_inference_req req;
        if (copy_from_user(&req, uarg, sizeof(req))) {
            ret = -EFAULT;
            break;
        }

        // Setup DMA addresses
        accel_write_reg(adev, REG_DMA_SRC, req.model_addr);
        accel_write_reg(adev, REG_DMA_DST, req.input_addr);
        accel_write_reg(adev, REG_PRECISION, req.precision);

        adev->inference_done = false;

        // Start inference
        accel_write_reg(adev, REG_CONTROL, CTRL_START);
        break;
    }

    case ACCEL_WAIT_DONE: {
        struct accel_status status;
        ret = wait_event_interruptible(adev->waitq, adev->inference_done);
        if (ret)
            break;

        status.status = accel_read_reg(adev, REG_STATUS);
        status.layer_index = accel_read_reg(adev, REG_LAYER_INDEX);
        status.latency = accel_read_reg(adev, REG_LATENCY);

        if (copy_to_user(uarg, &status, sizeof(status)))
            ret = -EFAULT;
        break;
    }

    case ACCEL_GET_STATUS: {
        struct accel_status status;
        status.status = accel_read_reg(adev, REG_STATUS);
        status.layer_index = accel_read_reg(adev, REG_LAYER_INDEX);
        status.latency = accel_read_reg(adev, REG_LATENCY);

        if (copy_to_user(uarg, &status, sizeof(status)))
            ret = -EFAULT;
        break;
    }

    case ACCEL_DMA_MAP: {
        struct accel_dma_req req;
        dma_addr_t dma_addr;
        void *cpu_addr;

        if (copy_from_user(&req, uarg, sizeof(req))) {
            ret = -EFAULT;
            break;
        }

        cpu_addr = dma_alloc_coherent(&adev->pdev->dev, req.size,
                                      &dma_addr, GFP_KERNEL);
        if (!cpu_addr) {
            ret = -ENOMEM;
            break;
        }

        if (copy_from_user(cpu_addr, (void __user *)req.user_addr, req.size)) {
            dma_free_coherent(&adev->pdev->dev, req.size, cpu_addr, dma_addr);
            ret = -EFAULT;
            break;
        }

        req.dma_addr = dma_addr;
        if (copy_to_user(uarg, &req, sizeof(req)))
            ret = -EFAULT;
        break;
    }

    default:
        ret = -ENOTTY;
        break;
    }

    mutex_unlock(&adev->lock);
    return ret;
}

static int accel_open(struct inode *inode, struct file *f)
{
    struct accel_dev *adev = container_of(inode->i_cdev, struct accel_dev, cdev);
    f->private_data = adev;
    return 0;
}

static const struct file_operations accel_fops = {
    .owner          = THIS_MODULE,
    .unlocked_ioctl = accel_ioctl,
    .open           = accel_open,
};

static int accel_setup_chardev(struct accel_dev *adev, int index)
{
    int ret;
    dev_t devt;

    ret = alloc_chrdev_region(&devt, 0, 1, DEVICE_NAME);
    if (ret < 0)
        return ret;

    adev->devt = devt;
    major_num = MAJOR(devt);

    cdev_init(&adev->cdev, &accel_fops);
    adev->cdev.owner = THIS_MODULE;

    ret = cdev_add(&adev->cdev, devt, 1);
    if (ret)
        goto err_cdev;

    accel_class = class_create(THIS_MODULE, DRV_NAME);
    if (IS_ERR(accel_class)) {
        ret = PTR_ERR(accel_class);
        goto err_class;
    }

    device_create(accel_class, NULL, devt, NULL, DEVICE_NAME "%d", index);

    return 0;

err_class:
    cdev_del(&adev->cdev);
err_cdev:
    unregister_chrdev_region(devt, 1);
    return ret;
}

static int accel_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    struct accel_dev *adev;
    int err, index;

    adev = devm_kzalloc(&pdev->dev, sizeof(*adev), GFP_KERNEL);
    if (!adev)
        return -ENOMEM;

    adev->pdev = pdev;
    mutex_init(&adev->lock);
    init_waitqueue_head(&adev->waitq);

    err = pcim_enable_device(pdev);
    if (err)
        return err;

    err = pci_request_regions(pdev, DRV_NAME);
    if (err)
        return err;

    adev->bar0 = pcim_iomap(pdev, 0, 0);
    if (!adev->bar0)
        return -ENOMEM;

    // Request MSI interrupt
    err = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_MSI);
    if (err < 0)
        return err;

    adev->irq = pci_irq_vector(pdev, 0);
    err = request_irq(adev->irq, accel_irq_handler, 0, DRV_NAME, adev);
    if (err)
        goto err_irq;

    // Setup DMA
    err = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (err)
        goto err_dma;

    index = num_devices++;
    accel_devices[index] = adev;

    err = accel_setup_chardev(adev, index);
    if (err)
        goto err_chardev;

    pci_set_drvdata(pdev, adev);
    pci_set_master(pdev);

    dev_info(&pdev->dev, "AI Accelerator initialized\n");
    return 0;

err_chardev:
err_dma:
    free_irq(adev->irq, adev);
err_irq:
    pci_free_irq_vectors(pdev);
    return err;
}

static void accel_remove(struct pci_dev *pdev)
{
    struct accel_dev *adev = pci_get_drvdata(pdev);
    int i;

    if (!adev)
        return;

    // Find and remove from devices array
    for (i = 0; i < num_devices; i++) {
        if (accel_devices[i] == adev) {
            accel_devices[i] = NULL;
            break;
        }
    }

    device_destroy(accel_class, adev->devt);
    class_destroy(accel_class);
    cdev_del(&adev->cdev);
    unregister_chrdev_region(adev->devt, 1);

    free_irq(adev->irq, adev);
    pci_free_irq_vectors(pdev);
    pci_release_regions(pdev);
}

static struct pci_device_id accel_pci_ids[] = {
    { PCI_DEVICE(PCI_VENDOR_ID_ACCEL, PCI_DEVICE_ID_ACCEL) },
    { 0, }
};
MODULE_DEVICE_TABLE(pci, accel_pci_ids);

static struct pci_driver accel_pci_driver = {
    .name     = DRV_NAME,
    .id_table = accel_pci_ids,
    .probe    = accel_probe,
    .remove   = accel_remove,
};

module_pci_driver(accel_pci_driver);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("AI Accelerator Team");
MODULE_DESCRIPTION("PCIe driver for AI inference accelerator");
MODULE_VERSION("1.0");

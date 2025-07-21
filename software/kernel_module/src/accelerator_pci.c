// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define DRV_NAME "accel_pci"
#define PCI_VENDOR_ID_ACCEL 0x1D0F
#define PCI_DEVICE_ID_ACCEL 0x2000

struct accel_dev {
    struct pci_dev *pdev;
    void __iomem *bar0;
    struct dma_chan *dma_chan;
};

static struct pci_device_id accel_pci_ids[] = {
    { PCI_DEVICE(PCI_VENDOR_ID_ACCEL, PCI_DEVICE_ID_ACCEL) },
    { 0, }
};
MODULE_DEVICE_TABLE(pci, accel_pci_ids);

static long accel_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct accel_dev *adev = f->private_data;
    // handle user commands to sequencer
    return 0;
}

static int accel_open(struct inode *inode, struct file *f)
{
    f->private_data = pci_get_drvdata(container_of(inode->i_cdev, struct pci_dev, dev));
    return 0;
}

static const struct file_operations accel_fops = {
    .owner          = THIS_MODULE,
    .unlocked_ioctl = accel_ioctl,
    .open           = accel_open,
};

static int accel_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    struct accel_dev *adev;
    int err;

    adev = devm_kzalloc(&pdev->dev, sizeof(*adev), GFP_KERNEL);
    if (!adev)
        return -ENOMEM;

    err = pcim_enable_device(pdev);
    if (err)
        return err;

    err = pci_request_regions(pdev, DRV_NAME);
    if (err)
        return err;

    adev->bar0 = pcim_iomap(pdev, 0, 0);
    if (!adev->bar0)
        return -ENOMEM;

    adev->dma_chan = dma_request_chan(&pdev->dev, "dma0");
    if (IS_ERR(adev->dma_chan))
        adev->dma_chan = NULL;

    pci_set_drvdata(pdev, adev);

    return 0;
}

static void accel_remove(struct pci_dev *pdev)
{
    struct accel_dev *adev = pci_get_drvdata(pdev);

    if (adev->dma_chan)
        dma_release_channel(adev->dma_chan);
    pci_release_regions(pdev);
}

static struct pci_driver accel_pci_driver = {
    .name     = DRV_NAME,
    .id_table = accel_pci_ids,
    .probe    = accel_probe,
    .remove   = accel_remove,
};

module_pci_driver(accel_pci_driver);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("AI Accelerator Team");
MODULE_DESCRIPTION("PCIe driver for AI accelerator");

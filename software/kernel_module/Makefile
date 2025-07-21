obj-m := accelerator_pci.o

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
$(MAKE) -C $(KDIR) M=$(PWD)/src modules

clean:
$(MAKE) -C $(KDIR) M=$(PWD)/src clean

sign:
scripts/sign-file sha256 certs/signing_key.pem certs/signing_key.x509 src/accelerator_pci.ko


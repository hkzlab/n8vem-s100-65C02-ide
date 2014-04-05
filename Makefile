AS = xa
ASFLAGS = -v

BINDIR = bin
SRCDIR = src

$(BINDIR)/65ide:	$(SRCDIR)/65ide.asm
	$(AS) $(ASFLAGS) $(SRCDIR)/65ide.asm -o $(BINDIR)/65ide

clean:
	rm -rf $(BINDIR)/*

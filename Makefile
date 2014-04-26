AS = xa
ASFLAGS = -v

BIN_DIR=bin/
SRC_DIR=src/
DEST_DIR=~/

$(BIN_DIR)/65ide: $(SRC_DIR)/65ide.asm
	$(AS) $(ASFLAGS) $(SRC_DIR)/65ide.asm -o $(BIN_DIR)/65ide

clean:
	rm -rf $(BIN_DIR)/*

install: $(BIN_DIR)/65ide
	cp	$(BIN_DIR)/65ide $(DEST_DIR)

BIN_DIR=bin/
SRC_DIR=src/
DEST_DIR=~/

AS = xa
ASFLAGS = -v -I$(SRC_DIR)

$(BIN_DIR)/65ide: $(SRC_DIR)/main.a65 $(SRC_DIR)/n8vem-ide.a65 $(SRC_DIR)/console.a65
	$(AS) $(ASFLAGS) $(SRC_DIR)/main.a65 -o $(BIN_DIR)/65ide

clean:
	rm -rf $(BIN_DIR)/*

install: $(BIN_DIR)/65ide
	xmodem -m 8N1 -s 19200 -p /dev/cu.usbserial -i $(BIN_DIR)/65ide

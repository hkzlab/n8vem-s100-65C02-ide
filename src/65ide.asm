#define IO				$F000
#define CONDATA			IO+$01
#define CONSTATUS		IO+$00

; 8255 I/O modes
#define CFG8255_INPUT	#%10010010
#define CFG8255_OUTPUT	#%10000000

; IDE
#define IDEctrl			IO+$33
#define IDEportA		IO+$30
#define IDEportB		IO+$31
#define IDEportC		IO+$32

#define IDEa0line		$01
#define IDEa1line		$02
#define IDEa2line		$04
#define IDEcs0line		$08
#define IDEcs1line		$10
#define IDEwrline		$20
#define IDErdline		$40
#define IDErstline		$80

// IDE Registers
#define REGdata			#$0 + IDEcs0line
#define REGerr			#$0 + IDEcs0line + IDEa0line
#define REGseccnt		#$0 + IDEcs0line + IDEa1line
#define REGsector		#$0 + IDEcs0line + IDEa1line + IDEa0line
#define REGCylLOW		#$0 + IDEcs0line + IDEa2line
#define REGCylHIGH		#$0 + IDEcs0line + IDEa2line + IDEa0line
#define REGshd			#$0 + IDEcs0line + IDEa2line + IDEa1line
#define REGcommand		#$0 + IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGstatus		#$0 + IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGcontrol		#$0 + IDEcs1line + IDEa2line + IDEa1line
#define REGastatus		#$0 + IDEcs1line + IDEa2line + IDEa1line + IDEa0line

// IDE Commands
#define COMMANDrecal	#$10
#define	COMMANDread		#$20
#define COMMANDwrite	#$30
#define COMMANDinit		#$91
#define COMMANDid		#$EC
#define COMMANDspindown	#$E0
#define	COMMANDspinup	#$E1

// Local variables
#define ZERO_SCRATCH_BASE $40
#define STR_POINTER		ZERO_SCRATCH_BASE + $0
#define SCRATCH_POINTER	ZERO_SCRATCH_BASE + $2
#define	PREVIOUS_CHAR	ZERO_SCRATCH_BASE + $4

// Location memory which contains the start address (16 bit) of IDE sector buffer (256x16bit words = 512 bytes)
#define IDE_SECTOR_BUFFER_ADDR	$80

// Number of logical cylinders is in word 1
#define IDE_IDENT_CYL_OFFSET $2
// Number of logical heads is in word 3
#define IDE_IDENT_HEAD_OFFSET $6
// Number of logical sector per track is in word 6
#define IDE_IDENT_SEC_OFFSET $C

#define IDbuffer $3000

#define IDE_DISKDATA_BASE IDbuffer + $200

* = IDE_DISKDATA_BASE
IDE_DISKDATA_CYLINDERS:	.word	$0000
IDE_DISKDATA_HEADS:		.word	$0000
IDE_DISKDATA_SECTORS:	.word	$0000

* = $5000
MAIN:	.(
			sei			// Disable interrupts (Start Of ROM Code) 
			ldx	#$FF	// Set stack pointer
			txs			// to 0xFF (actualy 0x01FF, as high byte is always 1!)

			lda	#0		// Clear RAM at 0x0000 (Useful for debugging only)
			tay			// Fill first page with 0's
CLEAR2: 	
			sta	$0000,Y		// Set pointer Y -> 0
			iny
			bne	CLEAR2

			jsr PRINT_TITLE
			nop

			// Init IDE
			jsr IDEInit
			nop

			// Print ID
			ldx	#>IDbuffer
			ldy #<IDbuffer
			jsr IDEGetID
			jsr IDEExtractInfo

			lda	#$2E
			sta STR_POINTER
			lda #$30
			sta STR_POINTER+1
			jsr PRINT_STRING

			lda	#$14
			sta STR_POINTER
			lda #$30
			sta STR_POINTER+1
			jsr PRINT_STRING

			// Init IDE
			jsr IDEInit
			nop

			// Try to read sector
			ldx #$00
			ldy #$01
			lda #$01
			jsr IDErdSector
			nop

			// Return to the monitor
			jmp $F100
		.)

// ****** CODE IDE ******

/* IDE Drive initialization
 * INVALIDATED REGISTERS:
 *	- A
 *
 * PARAMETERS:
 * RETURNS: 
 *	- A: Init status (00: OK, FF: KO)
 */
IDEInit:	.(
			// Save the used registers on stack
			phx
			phy
			php

			// Set the 8255 to INPUT
			sta	IDEctrl

			// Reset the IDE drive
			jsr IDEReset

			// Deassert all IDE control lines
			lda #$00
			sta IDEportC

			// Add a delay here
			pha
			lda #$FF
			jsr DELAY
			pla		

			// Configure SHD (Sector, Head, Drive) register:
			// Data for IDE SDH reg (512bytes, LBA mode,single drive,head 0000)
			// For Trk,Sec,head (non LBA) use 10100000
			ldx REGshd
			ldy #%11100000
			jsr IDEwr8D // Send the command

			// Check we're ready (255 tries)
			ldx #$FF
ReadyLoop:
			phx
			lda REGstatus	// Read the status reg...
			jsr IDErd8D
			and	#$80		// ... and check that the busy flag went off!
			beq BDoneInit
			
			// DELAY
			jsr BIGDELAY	// Wait a lot in here
			
			plx
			dex
			bne ReadyLoop

			// If we got here, we couldn't get the BUSY flag to go off, something BAD happened...
			jsr PRINT_ERROR

			// Prepare the return value
			lda #$FF

DoneInit:
			jsr PRINT_DONE		

			// Restore from the stack
			plp
			ply
			plx

			rts

BDoneInit:	// If we got here, the busy flag went of: All is OK!
			plx

			// Prepare the return value
			lda #$00

			bra DoneInit
			.)

/* IDE Drive reset
 * INVALIDATED REGISTERS:
 * PARAMETERS:
 * RETURNS: 
 */
IDEReset:	.(
			// Save the regs
			pha
			phy
			php

			// Bring up the reset line
			lda #IDErstline
			sta IDEportC

			// And loop for a while...
			ldy $FF
ResetDelay:
			dey
			bne ResetDelay

			// Then turn it off
			lda #$00
			sta IDEportC
		
			// Restore from the stack
			plp
			ply
			pla

			rts
			.)

/* IDE busy/ready wait
 * INVALIDATED REGISTERS:
 *	- A
 *
 * PARAMETERS:
 * RETURNS: 
 *	- A: wait status (00: OK, FF: KO)
 */
IDEwaitnotbusy:	.(
			phx
			php

			// Prepare the high counter
			ldx #$FF

MoreWait:
			// Prepare the low counter
			lda #$FF

Wait:
			// Read the status register
			lda REGstatus
			jsr IDErd8D
			and	#%11000000 // Keep only the first 2 bits
			eor	#%01000000 // And check that bit 6 (DRIVE READY) is on and 7 (DRIVE BUSY) is off
			beq DoneNotBusy // Done!

			dec
			bne Wait // Do some wait
			dex
			beq DoneBusy // Do some more wait

			bra MoreWait

DoneBusy:
			// Prepare the return value: KO
			lda #$FF
			bra DoneReturn
DoneNotBusy:
			// Prepare the return value: OK
			lda #$00

DoneReturn:
			plp
			plx

			rts
		.)

/* IDE data request wait
 * INVALIDATED REGISTERS:
 *	- A
 *
 * PARAMETERS:
 * RETURNS: 
 *	- A: wait status (00: OK, FF: KO)
 */
IDEwaitdrq:	.(
			phx
			php

			// Prepare the high counter
			ldx #$FF

MoreWait:
			// Prepare the low counter
			lda #$FF

Wait:
			// Read the status register
			lda REGstatus
			jsr IDErd8D
			and	#%10001000 // Keep only bits 7 (BUSY) and 3 (DATA REQUEST)
			eor	#%00001000 // Check that drive is not busy and ready for a data transfer
			beq DoneNotBusy // Done!

			dec
			bne Wait // Do some wait
			dex
			beq DoneBusy // Do some more wait

			bra MoreWait

DoneBusy:
			// Prepare the return value: KO
			lda #$FF
			bra DoneReturn
DoneNotBusy:
			// Prepare the return value: OK
			lda #$00

DoneReturn:
			plp
			plx

			rts
		.)

/* IDE Get drive ID
 * INVALIDATED REGISTERS:
 *	- X,Y,A
 *
 * PARAMETERS:
 *	- X: Memory destination address (MSB)
 *  - Y: Memory destination address (LSB)
 * RETURNS:
 *  - A: Read result ($00: OK, $FF: KO)
 */
IDEGetID .(
			// Save the registers
			php

			// Temporarly save the destination address on the stack
			phx
			phy

			// Wait for the drive to be not busy
			jsr IDEwaitnotbusy
			and #$FF
			bne DoneBusy

			// Send ID command
			ldx REGcommand
			ldy COMMANDid
			jsr IDEwr8D

			// Wait for the drive to be ready for a data transfer...
			jsr IDEwaitdrq
			and #$FF
			bne DoneBusyDrq

			// Recover the destination address
			ply
			plx

			// Read ID into IDbuffer...
			jsr IDErd16D	
			and #$FF
			bne DoneReadError

			// Return OK
			lda #$00

			bra Done
			
DoneBusyDrq:
			// Return KO
			lda #$FF
			bra Done

DoneBusy:
			// Return KO
			lda #$FF
			bra Done

DoneReadError:
			// Return KO
			lda #$FF
			bra Done

Done:

			jsr PRINT_DONE

			// Restore the registers
			plp

			rts
		.)

/* IDE Extract information after reading drive ID
 * and populate a data structure.
 * Must be called on the address filled by IDEGetID
 * INVALIDATED REGISTERS:
 *	- X,Y
 *
 * PARAMETERS:
 *	- X: IDE info source address (MSB)
 *  - Y: IDE info source address (LSB)
 * RETURNS:
 */
IDEExtractInfo:	.(
				php
				pha

				// Save the address...
				sty ZERO_SCRATCH_BASE + $0
				stx ZERO_SCRATCH_BASE + $1

				// Load cylinders
				ldy IDE_IDENT_CYL_OFFSET
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...
				ldy IDE_IDENT_CYL_OFFSET+$1
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...

				// Load heads
				ldy IDE_IDENT_HEAD_OFFSET
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...
				ldy IDE_IDENT_HEAD_OFFSET+$1
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...

				// Load sectors
				ldy IDE_IDENT_SEC_OFFSET
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...
				ldy IDE_IDENT_SEC_OFFSET+$1
				lda (ZERO_SCRATCH_BASE),y
				// TODO Store...


				pla
				plp

				rts
			.)

/* IDE 16bit READ
 * INVALIDATED REGISTERS:
 *	- X,Y,A
 *
 * PARAMETERS:
 *	- X: Memory destination address (MSB)
 *  - Y: Memory destination address (LSB)
 * RETURNS:
 *  - A: Read result ($00: OK, $FF: KO)
 */
IDErd16D:	.(
			php

			// Save destination address for block buffer
			sty IDE_SECTOR_BUFFER_ADDR
			stx IDE_SECTOR_BUFFER_ADDR+1

			// Prepare to read 256 words = 512 bytes
			ldx #$00 // Trick: we decrement this before checking, so at first dex we get FF here...
			ldy #$00

BeginRead:
			// Set data register to read
			lda REGdata
			sta IDEportC

			// Assert read line
			ora #IDErdline
			sta IDEportC
		
			// Load first word part
			lda IDEportB // High byte
			sta (IDE_SECTOR_BUFFER_ADDR),Y // Save it
			iny // Increase destination address
			bne	RNByte // Check if we are increasing the address MSB
			
			lda IDE_SECTOR_BUFFER_ADDR+1
			adc 1
			sta IDE_SECTOR_BUFFER_ADDR+1
			ldy #$00

RNByte:
			// Load second word part
			lda IDEportA // Low byte
			sta (IDE_SECTOR_BUFFER_ADDR),Y // Save it
			iny
			bne ENRead
			
			lda IDE_SECTOR_BUFFER_ADDR+1
			adc 1
			sta IDE_SECTOR_BUFFER_ADDR+1
			ldy #$00
ENRead:
			// Check if we have read the last word or not...
			dex
			bne BeginRead

			// Deassert read line
			lda REGdata
			sta IDEportC

			// Get read status... and check for ERROR in bit 0
			lda REGstatus
			jsr IDErd8D
		
			// Load the return value here
			ldx #$00

			and #$01
			beq End

			// Rewrite return value for error
			ldx #$FF

End:
			txa // Put the return address in A

			plp

			rts
			.)


/* IDE read sector
 * INVALIDATED REGISTERS:
 *	- X,Y,A
 *
 * PARAMETERS:
 *  - A: Sector number
 *	- X: Cylinder HIGH 
 *  - Y: Cylinder LOW
 * RETURNS:
 *	- A: $00 OK, $FF ERROR
 */
IDErdSector:	.(
			php
		
			// Select the sector
			jsr IDESetLBA

			// Wait for disk not busy
			jsr IDEwaitnotbusy
			and #$FF
			bne DoneError
			
			// Send a read command
			ldx REGcommand
			ldy COMMANDread
			jsr IDEwr8D

			// Wait for the disk to be ready for transfer
			jsr IDEwaitdrq
			and #$FF
			bne DoneError
	
			// Read the sector!
			ldx #>IDE_SECTOR_BUFFER_ADDR
			ldy #<IDE_SECTOR_BUFFER_ADDR
			jsr IDErd16D

			and #$FF
			beq Done

DoneError:
			lda #$FF

Done:
			plp

			rts
			.)

/* IDE write sector
 * INVALIDATED REGISTERS:
 *	- X,Y,A
 *
 * PARAMETERS:
 *  - A: Sector number
 *	- X: Cylinder HIGH
 *  - Y: Cylinder LOW
 * RETURNS:
 *	- A: $00 OK, $FF ERROR
 */
IDEwrSector:	.(
			php
	
			// Write LBA data
			jsr IDESetLBA

			// Wait for disk not busy
			jsr IDEwaitnotbusy
			and #$FF
			bne DoneError

			// Send a write command
			ldx REGcommand
			ldy COMMANDwrite
			jsr IDEwr8D

			// Wait for the disk to be ready for transfer
			jsr IDEwaitdrq
			and #$FF
			bne DoneError

			// Set the 8255 to output mode
			lda	CFG8255_OUTPUT
			sta IDEctrl

			// Prepare to write 256 words = 512 bytes
			ldx #$00 // Trick: we decrement this before checking, so at first dex we get FF here...
			ldy #$00

BeginWrite:
			// Store first word part
			lda (IDE_SECTOR_BUFFER_ADDR),Y // Load it
			sta IDEportB // Save High byte
			iny // Increase source address
			bne	WNByte // Check if we are increasing the address MSB
			
			lda IDE_SECTOR_BUFFER_ADDR+1
			adc 1
			sta IDE_SECTOR_BUFFER_ADDR+1
			ldy #$00

WNByte:
			// Write second word part
			lda (IDE_SECTOR_BUFFER_ADDR),Y // Load it
			sta IDEportA // Low byte
			iny
			bne ENWrite
			
			lda IDE_SECTOR_BUFFER_ADDR+1
			adc 1
			sta IDE_SECTOR_BUFFER_ADDR+1
			ldy #$00
ENWrite:
			// Set data register to read
			lda REGdata
			sta IDEportC

			// Assert write line
			ora #IDEwrline
			sta IDEportC

			// Deassert it
			eor #IDEwrline
			sta IDEportC

			// Check if we have read the last word or not...
			dex
			bne BeginWrite

			// Set the 8255 to input mode
			lda	CFG8255_INPUT
			sta IDEctrl

			// Get read status... and check for ERROR in bit 0
			lda REGstatus
			jsr IDErd8D

			and #$01
			beq Done

DoneError:
			lda #$FF

Done:
			plp

			rts
				.)

/* IDE set LBA address
 * INVALIDATED REGISTERS:
 *	- X,Y,A
 *
 * PARAMETERS:
 *  - A: Sector number
 *	- X: Cylinder HIGH
 *  - Y: Cylinder LOW
 * RETURNS:
 *
 * WARNING: heads are ignored for now
 */
IDESetLBA:		.(
			php

			// Clear carry
			clc

			// A contains the sector number
			adc #$1 // Convert from 0 based numeration to 1 based (LBA)

			// Save the cylinder data on stack
			phx
			phy

			tya // Move it to Y

			// Send the sector (LBA5)
			ldx REGsector
			jsr IDEwr8D
			
			// Send cylinder LSB
			ply
			ldx REGCylLOW
			jsr IDEwr8D

			// Send cylinder MSB
			ply
			ldx REGCylHIGH
			jsr IDEwr8D

			// Then set to read one sector
			ldy #$01
			ldx REGseccnt
			jsr IDEwr8D

			plp

			rts
			.)

// IDE Low level 8bit I/O

/* IDE 8bit READ
 * INVALIDATED REGISTERS:
 *	- A
 *
 * PARAMETERS:
 *	- A: Register to read
 * RETURNS: 
 *	- A: wait status (00: OK, FF: KO)
 */
IDErd8D:	.(
			// Save used registers
			phx
			php

			// Set register to read...
			sta IDEportC
		
			// Set the read line high...
			ora	#IDErdline
			sta IDEportC

			// Read the output from drive
			// ...and save it on the stack for now
			ldx IDEportA
			phx
	
			// Set the read line low
			eor	#IDErdline
			sta IDEportC
		
			// Clear the register
			lda #$00
			sta IDEportC

			// Load the result we saved on the stack
			pla

			// Recover the registers
			plp
			plx
			
			rts
			.)

/* IDE 8bit Write
 * INVALIDATED REGISTERS:
 *	- X,Y
 *
 * PARAMETERS:
 *	- X: IDE Register to write on
 *  - Y: Value to write on register
 * RETURNS: 
 */
IDEwr8D:	.(
			// Save the used registers
			pha
			php

			// Set the 8255 to output mode
			lda	CFG8255_OUTPUT
			sta IDEctrl

			// Write the data on the output	
			sty IDEportA

			// Select the register
			txa
			sta IDEportC

			// Assert the write line
			ora #IDEwrline
			sta IDEportC
			// Then deassert it...
			eor #IDEwrline
			sta IDEportC

			// Deselect the register
			lda #$00
			sta IDEportC

			// Reset the 8255 to input mode
			lda CFG8255_INPUT
			sta IDEctrl
	
			// Recover used registers
			plp
			pla

			rts
			.)

// ******* UTILITY FUNCTIONS *******
PRINT_DEB:	.(
		pha
		lda	#<PDEB01
		sta STR_POINTER
		lda #>PDEB01
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_TITLE:	.(
		pha
		lda	#<PTITLE
		sta STR_POINTER
		lda #>PTITLE
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_ERROR:	.(
		pha
		lda	#<PERROR
		sta STR_POINTER
		lda #>PERROR
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_DONE:	.(
		pha
		lda	#<PDONE
		sta STR_POINTER
		lda #>PDONE
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_STRING:	.(
STR2:
		lda (STR_POINTER)
		cmp #0
		beq STRING_DONE
		jsr	CONOUT
		inc STR_POINTER // Increment LSB
		bne STR2
		inc STR_POINTER+1 // We need to increment MSB
		jmp STR2
STRING_DONE:
		rts
		.)

// ******* HARDWARE I/O *******

//
// Propeller I/O subroutines
//
// Print character to propeller console
CONOUT:	.(
		pha
CONOUT1:
		lda #%00000100
		and CONSTATUS
		beq CONOUT1
		pla
		sta CONDATA
		rts
		.)

// Get character from console
CONIN:	.(
		lda #%00000010
		and CONSTATUS
		beq CONIN
		lda CONDATA
		sta PREVIOUS_CHAR
		rts
		.)

///////
DELAY:	.(
		bra DELAYA
DLY0:
		sbc #7
DELAYA:	
		cmp #7
		bcs	DLY0
		lsr
		bcs	DLY1
DLY1:
		beq	DLY2
		lsr
		beq	DLY3
		bcc DLY3
DLY2:
		bne	DLY3
DLY3:
		rts
		.)

BIGDELAY:	.(
		pha
		phx
		phy

		lda	#$FF
BDLOOP:
		pha
		lda #$FF
		jsr DELAY
		pla
		dec
		bne BDLOOP
		
		ply
		plx
		pla

		rts
		.)

PTITLE:	.asc "IDE BOARD TESTER",$07,$07,$07,$07,$07,$0a,$0d,0
PERROR:	.asc "ERROR",$07,$07,$0a,$0d,0
PERRORRD16:	.asc "ERROR RD16",$07,$07,$0a,$0d,0
PDONE:	.asc "DONE",$07,$07,$0a,$0d,0
PBUSY:	.asc "IDE BUSY",$0a,$0d,0
PBUSYDRQ:	.asc "IDE BUSY DRQ",$0a,$0d,0

PBREAD:	.asc "BREAD",$0a,$0d,0

PDEB01:	.asc "DEB01",$0a,$0d,0
PDEB02:	.asc "DEB02",$0a,$0d,0

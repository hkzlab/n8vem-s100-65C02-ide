#define IO				$F000
#define CONDATA			IO+$01
#define CONSTATUS		IO+$00

/**** 8255 I/O modes ****/
#define CFG8255_INPUT	#%10010010
#define CFG8255_OUTPUT	#%10000000

/**** IDE ****/
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

#define REGdata			#$0 + IDEcs0line
#define REGerr			#$0 + IDEcs0line + IDEa0line
#define REGseccnt		#$0 + IDEcs0line + IDEa1line
#define REGsector		#$0 + IDEcs0line + IDEa1line + IDEa0line
#define REGcylinderLSB	#$0 + IDEcs0line + IDEa2line
#define REGcylinderMSB	#$0 + IDEcs0line + IDEa2line + IDEa0line
#define REGshd			#$0 + IDEcs0line + IDEa2line + IDEa1line
#define REGcommand		#$0 + IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGstatus		#$0 + IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGcontrol		#$0 + IDEcs1line + IDEa2line + IDEa1line
#define REGastatus		#$0 + IDEcs1line + IDEa2line + IDEa1line + IDEa0line

#define COMMANDrecal	#$10
#define	COMMANDread		#$20
#define COMMANDwrite	#$30
#define COMMANDinit		#$91
#define COMMANDid		#$EC
#define COMMANDspindown	#$E0
#define	COMMANDspinup	#$E1

/************/

#define	PREVIOUS_CHAR	$50
#define STR_POINTER		$40

#define SCRATCHA		$45
#define SCRATCHB		SCRATCHA+1
#define SCRATCHC		SCRATCHA+2
#define SCRATCHD		SCRATCHA+3

#define ADDRSCRATCH		$80

#define IDbuffer		$3000

* = $5000
MAIN:	.(
			sei			;Disable interrupts (Note Start Of ROM Code) 
			ldx	#$FF	;Set stack pointer
			txs			;to 0FFH 

			lda	#0		;Clear RAM at 0000H (Useful for debugging only)
			tay			;Fill first page with 0's
CLEAR2: 	
			sta	$0000,Y		;Set pointer Y -> 0
			iny
			bne	CLEAR2

			jsr PRINT_TITLE
			nop
			jsr IDEInit
			nop
			jsr IDEGetID 

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

			jmp $F100
		.)

// ****** IDE ******

// IDE Drive initialization
// PARAMETERS - none
// RETURNS - nothing
IDEInit:	.(
			// Save the used registers on stack
			pha
			phx
			phy
			php

			// Clear the ZERO flag
			lda #$FF 
			and #$FF

			// Set the 8255 to INPUT
			lda	CFG8255_INPUT
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

DoneInit:
			jsr PRINT_DONE		

			// Restore from the stack
			plp
			ply
			plx
			pla

			rts

BDoneInit:	// If we got here, the busy flag went of: All is OK!
			plx
			bra DoneInit
			.)

// IDE Reset code
// PARAMETERS - none
// RETURNS - nothing
IDEReset:	.(
			// Save the regs
			pha
			phy
			php

			// Bring up the reset line
			lda IDErstline
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

// Returns
// A <- 0 OK
// A <- FF ERROR
IDEwaitnotbusy:	.(
			lda #$FF
			sta SCRATCHA
MoreWait:
			lda #$FF
Wait:
			lda REGstatus
			jsr IDErd8D
			and	#%11000000
			eor	#%01000000
			beq DoneNotBusy
			dec
			bne Wait
			lda SCRATCHA
			dec
			beq DoneBusy
			sta SCRATCHA
			bra MoreWait
DoneBusy:
			lda #$FF
			rts
DoneNotBusy:
			lda #$00
			rts
		.)

// Returns
// A <- 0 OK
// A <- FF ERROR
IDEwaitdrq:	.(
			lda #$FF
			sta SCRATCHA
MoreWait:
			lda #$FF
Wait:
			lda REGstatus
			jsr IDErd8D
			and	#%10001000
			eor	#%00001000
			beq DoneDRQ
			dec
			bne Wait
			lda SCRATCHA
			dec
			beq DoneBusy
			sta SCRATCHA
			bra MoreWait
DoneBusy:
			lda #$FF
			rts
DoneDRQ:
			lda #$00
			rts
		.)

IDEGetID .(
			pha
			phx
			phy

			jsr IDEwaitnotbusy
			and #$FF
			bne DoneBusy

			ldx REGcommand
			ldy COMMANDid
			jsr IDEwr8D

			jsr IDEwaitdrq
			and #$FF
			bne DoneBusyDrq

			// Read ID into IDbuffer...
			ldx	#>IDbuffer
			ldy #<IDbuffer
			jsr IDErd16D	
			
			bra Done
			
DoneBusyDrq:
			jsr PRINT_BUSY_DRQ
			bra Done
DoneBusy:
			jsr PRINT_BUSY
			bra Done
Done:

			jsr PRINT_DONE

			ply
			plx
			pla

			rts
		.)

// IDE Low level 16bit I/O
// Parameters
// X -> MSB Dest. address
// Y -> LSB Dest. address
IDErd16D:	.(
			phy
			phx
			pha

			sty ADDRSCRATCH
			stx ADDRSCRATCH+1

			ldx #$00
			ldy #$00
BeginRead:
			lda REGdata
			sta IDEportC

			ora IDErdline
			sta IDEportC
			
			lda IDEportB // High byte
			sta (ADDRSCRATCH),Y
			iny
			bne	RNByte
			
			lda ADDRSCRATCH+1
			adc 1
			sta ADDRSCRATCH+1
			ldy #$00
RNByte:
			lda IDEportA // Low byte
			sta (ADDRSCRATCH),Y
			iny
			bne ENRead
			
			lda ADDRSCRATCH+1
			adc 1
			sta ADDRSCRATCH+1
			ldy #$00
ENRead:
			// Check if we have finished one byte
			dex
			bne BeginRead

			// Deassert read line
			lda REGdata
			sta IDEportC

			// Read status
			lda REGstatus
			jsr IDErd8D
			and #$01
			beq End

			jsr PRINT_ERRORRD16R

End:
			pla
			plx
			ply

			rts
			.)

IDEwr16D:	.(
			rts
			.)

// IDE Low level 8bit I/O

// IDE Register read
// Parameters
//  A -> Register to read
// Returns
//	A <- Read value
IDErd8D:	.(
			sta IDEportC
			
			ora	IDErdline
			sta IDEportC

			ldx IDEportA
			phx
		
			eor	IDErdline
			sta IDEportC
			
			lda #$00
			sta IDEportC

			pla
			sta SCRATCHA

			rts
			.)


// IDE Register write
// Parameters
//  X -> IDE Register to write on
//  Y -> Value to write on register
// Returns
// 	Nothing
IDEwr8D:	.(
			lda	CFG8255_OUTPUT
			sta IDEctrl


			sty IDEportA
			txa
			sta IDEportC


			ora IDEwrline
			sta IDEportC
			eor IDEwrline
			sta IDEportC


			lda #$00
			sta IDEportC


			lda CFG8255_INPUT
			sta IDEctrl
			

			rts
			.)

// ******* UTILITY FUNCTIONS *******
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

PRINT_ERRORRD16R:	.(
		pha
		lda	#<PERRORRD16
		sta STR_POINTER
		lda #>PERRORRD16
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

PRINT_DEB01:	.(
		pha
		lda	#<PDEB01
		sta STR_POINTER
		lda #>PDEB01
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_DEB02:	.(
		pha
		lda	#<PDEB02
		sta STR_POINTER
		lda #>PDEB02
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_BUSY:	.(
		pha
		lda	#<PBUSY
		sta STR_POINTER
		lda #>PBUSY
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_BREAD:	.(
		pha
		lda	#<PBREAD
		sta STR_POINTER
		lda #>PBREAD
		sta STR_POINTER+1
		jsr PRINT_STRING
		pla

		rts
		.)

PRINT_BUSY_DRQ:	.(
		pha
		lda	#<PBUSYDRQ
		sta STR_POINTER
		lda #>PBUSYDRQ
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
		inc STR_POINTER ; Increment LSB
		bne STR2
		inc STR_POINTER+1 ; We need to increment MSB
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

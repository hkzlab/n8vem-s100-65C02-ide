#define IO				$F000
#define CONDATA			IO+$01
#define CONSTATUS		IO+$00

/**** 8255 ****/
#define READcfg8255		#%10010010
#define WRITEcfg8255	#%10000000

/**** IDE ****/
#define IDEctrl			IO+$33
#define IDEportA		IO+$30
#define IDEportB		IO+$31
#define IDEportC		IO+$32

#define IDEa0line		#$01
#define IDEa1line		#$02
#define IDEa2line		#$04
#define IDEcs0line		#$08
#define IDEcs1line		#$10
#define IDEwrline		#$20
#define IDErdline		#$40
#define IDErstline		#$80

//#define REGdata			IDEcs0line
#define REGdata			#%00001000
#define REGerr			IDEcs0line + IDEa0line
#define REGseccnt		IDEcs0line + IDEa1line
#define REGsector		IDEcs0line + IDEa1line + IDEa0line
#define REGcylinderLSB	IDEcs0line + IDEa2line
#define REGcylinderMSB	IDEcs0line + IDEa2line + IDEa0line
//#define REGshd			IDEcs0line + IDEa2line + IDEa1line
#define REGshd			#%00001110
//#define REGcommand		IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGcommand		#%00001111
//#define REGstatus		IDEcs0line + IDEa2line + IDEa1line + IDEa0line
#define REGstatus		#%00001111	
#define REGcontrol		IDEcs1line + IDEa2line + IDEa1line
#define REGastatus		IDEcs1line + IDEa2line + IDEa1line + IDEa0line

#define COMMANDrecal	#$10
#define	COMMANDread		#$20
#define COMMANDwrite	#$30
#define COMMANDinit		#$91
#define COMMANDid		#$0EC
#define COMMANDspindown	#$0E0
#define	COMMANDspinup	#$0E1

/************/

#define	PREVIOUS_CHAR	$50
#define STR_POINTER		$40

#define SCRATCHA		$45
#define SCRATCHB		SCRATCHA+1
#define SCRATCHC		SCRATCHA+2
#define SCRATCHD		SCRATCHA+3

#define IDbuffer		$1500

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
			jsr IDEInit

			jmp $F100
		.)

// ****** IDE ******

// IDE Drive initialization
IDEInit:	.(
			pha

			lda #$FF // Clear zero flag
			and #$FF

			lda	READcfg8255
			sta	IDEctrl

			jsr IDEReset

			lda #$00
			sta IDEportC

			// DELAY
			pha
			lda #$FF
			jsr DELAY
			pla		

			ldx REGshd
			ldy #%11100000
			jsr IDEwr8D

			ldx #$10
ReadyLoop:
			phx
			lda REGstatus
			jsr IDErd8D
			and	#$80
			beq DoneInit
			
			// DELAY
			pha
			lda #$FF
			jsr DELAY
			pla		
			
			plx
			dex
			bne ReadyLoop
			jsr PRINT_ERROR

DoneInit:
			jsr PRINT_DONE		

			pla
			rts
			.)

// IDE Reset code
// Takes no parameters...
IDEReset:	.(
			pha
			phy

			lda IDErstline
			sta IDEportC

			ldy $FF
ResetDelay:
			dey
			bne ResetDelay

			lda #$00
			sta IDEportC
			
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

			clc // Clear carry

			sty SCRATCHA
			stx SCRATCHA+1

			lda #$FF
			sta SCRATCHC
			lda #$01
			sta SCRATCHD

BeginRead:
			lda REGdata
			sta IDEportC

			ora IDErdline
			sta IDEportC
			
			lda IDEportA // Low byte
			sta (SCRATCHA)
			
			clc
			lda SCRATCHA
			adc 1
			sta SCRATCHA
			bcc RNByte
			lda SCRATCHA+1
			adc 1
			sta SCRATCHA+1

RNByte:
			lda IDEportB // High byte
			sta (SCRATCHA)

			clc
			lda SCRATCHA
			adc 1
			sta SCRATCHA
			bcc ENRead
			lda SCRATCHA+1
			adc 1
			sta SCRATCHA+1

			// Check if we have finished one byte
			lda SCRATCHC
			ldx SCRATCHC
			dex
			stx SCRATCHC
			and #$FF
			bne BeginRead

			// Check if we have another one to copy
			lda SCRATCHD
			ldx #$00
			stx SCRATCHD
			and #$FF
			bne BeginRead

ENRead:
			// Deassert read line
			lda REGdata
			sta IDEportC

			// Read status
			lda REGstatus
			jsr IDErd8D
			and #$01
			bne End

			jsr PRINT_ERRORRD16R

End:
			pla
			phx
			phy

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
			jsr PRINT_DEB01

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
			jsr PRINT_DEB02

			lda	WRITEcfg8255
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

			lda READcfg8255
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
		lda	#$01
		sta SCRATCHB
		lda #$FF
		sta SCRATCHA
BDELA:
		dec SCRATCHB
		beq DECA
DELOOP
		lda #$FF
		jsr DELAY

		bra BDELA
DELEND:
		pla
		rts
DECA:
		DEC SCRATCHA
		beq DELEND
		lda #$FF
		sta SCRATCHB
		bra DELOOP
		.)

PTITLE:	.asc "IDE BOARD TESTER",$07,$07,$07,$07,$07,$0a,$0d,0
PERROR:	.asc "ERROR",$07,$07,$0a,$0d,0
PERRORRD16:	.asc "ERROR RD16",$07,$07,$0a,$0d,0
PDONE:	.asc "DONE",$07,$07,$0a,$0d,0
PBUSY:	.asc "IDE BUSY",$0a,$0d,0
PBUSYDRQ:	.asc "IDE BUSY DRQ",$0a,$0d,0

PDEB01:	.asc "DEB01",$0a,$0d,0
PDEB02:	.asc "DEB02",$0a,$0d,0

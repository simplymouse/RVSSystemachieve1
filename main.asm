;
; Achieve1.asm
;
; Created: 02.06.2020 18:20:30
; Author : Simplymouse
;


; Replace with your application code

.include "m8def.inc"
.def symb = r20
.def st1 = r19
.def st0 = r18
.equ FCK = 8000000   
.equ Bitrate = 9600
.equ BAUD = FCK / (16 * Bitrate) - 1
.equ Timer1_interval = 35 
.equ Timer2_interval = 50
;.set Timer1_STR = "ping\r\n"
;.set Timer2_STR = "pong\r\n"
.DSEG				; Начало работы RAM
.CSEG				; начало сегмента кода
.org 0x000
rjmp RESET ; Reset Handler
.org $003
rjmp TIM2_COMP ; Timer2 Compare Handler
.org $004
rjmp TIM2_OVF ; Timer2 Overflow Handler
.org $006
rjmp TIM1_COMPA ; Timer1 CompareA Handler
.org $007
rjmp TIM1_COMPB ; Timer1 CompareB Handler
.org $00b
rjmp USART_RXC ; USART RX Complete Handler
;rjmp return : UDR Empty Handler
.org $00d
rjmp USART_TXC ; USART TX Complete Handler
;- - - - - - - - -Reset- - - - - - - - -
Reset:
	ldi R16, Low(RAMEND); младший байт конечного адреса ОЗУ в R16
	out SPL, R16        ; установка младшего байта указателя стека
	ldi R16, High(RAMEND); старший байт конечного адреса ОЗУ в R16
	out SPH, R16        ; установка старшего байта указателя стека

	;- - - - - - - - -TCNT- - - - - - - - -
	ldi st0,0x00 
	ldi st1,0x01
	out TCNT1H,st0	;Timer1
	out TCNT1L,st1
	out TCNT2,st1	;Timer2

	;- - - - - - - - -Timer 1 OCR- - - - - - - - -
	out OCR1AH, st1
	out OCR1AL, st1	; for OCR 1 byte (OVF) [if OCIE1A = (0); without interval]
	out OCR1BH, st0
	ldi r16, low(Timer1_interval)
	out OCR1BL,r16  ; for OCR intervar

	;- - - - - - - - -Timer 2 OCR_interval- - - - - - - - -
	ldi r16, Timer2_interval
	out OCR2, r16
 
	;- - - - - - - - -TIMSK- - - - - - - - -
	ldi r16,0b11011000;1<<OCIE2|1<<TOIE2|1<<OCIE1A|1<<OCIE1B|1<<TOIE1
	out TIMSK, r16

	;- - - - - - - - -USART- - - - - - - - -
	ldi r17, high(BAUD)
	out UBRRH, r17
	ldi r17, low(BAUD)
	out UBRRL, r17
	ldi r17,(1<<RXCIE)|(1<<TXCIE)|(1<<RXEN)|(1<<TXEN) ;разрешение приема-передачи
	out UCSRB,r17
	;ldi r17, (1<<URSEL)|(1<<UCSZ0) ;UCSZ0=1, UCSZ1=1, формат 8n1 /*|(1<<USBS)*/
	;out UCSRC,r17
	ldi r17, 0b10000110
	out UCSRC, r17
	;message
	ldi		YL,LOW(2*Timer1_STR)			; load Y pointer with
	ldi		YH,HIGH(2*Timer1_STR)			; myStr address
	;pong
	ldi		ZL,LOW(2*Timer2_STR)			; load Z pointer with
	ldi		ZH,HIGH(2*Timer2_STR)			; myStr address

	; Timers TCCR
	ldi r16, 0b00000000	;bit: COM1A1 COM1A0 COM1B1 COM1B0 FOC1A FOC1B WGM11 WGM10
	out TCCR1A, r16
	ldi r16, 0b00000001 ;1<<CS00|1<<CS01 ; prescaler 64  
	out TCCR1B, r16
	ldi r16,0b00000001 ; prescaler 64 CS12(1) 00000111(1024)
	out TCCR2, r16

	sei					; Разрешаем прерывания SREG I
;- - - - - - - - -Start- - - - - - - - -
start:
    rjmp start

TIM1_COMPA:		;TIM1_OVF
cli;
ldi st0,0x00;
ldi st1,0x01
out TCNT1H, st0
out TCNT1L, st1
sei 
reti

TIM2_OVF:
cli;
ldi st1, 0x01
out TCNT2, st1
sei 
reti

TIM1_COMPB:		; message
cli;
ld symb,Y+		; 1 tact
sts UDR, symb	; 2 tact
out TCNT1L, st1	; 3 tact
rcall send1
sei
reti

TIM2_COMP:		; message
cli;
ld symb,Z+		; 1 tact
sts UDR, symb	; 2 tact
out TCNT1L, st1	; 3 tact
rcall send2
sei
reti

send1:
ld symb,Y+
cpi	symb,$00
breq stopstring1
send_wait1:
		lds		r16,UCSRA	; load UCSR0A into r17
		sbrs	r16,UDRE	; wait for empty transmit buffer
		rjmp	send_wait1	; repeat loop	
sts UDR, symb
rjmp send1
stopstring1:
ret

send2:
ld symb,Z+
cpi	symb,$00
breq stopstring2
send_wait2:
		lds		r16,UCSRA	; load UCSR0A into r17
		sbrs	r16,UDRE	; wait for empty transmit buffer
		rjmp	send_wait1	; repeat loop	
sts UDR, symb
rjmp send1
stopstring2:
ret

USART_TXC:
; Wait for empty transmit buffer
lds	 r17,UCSRA	
sbrs r17,UDRE
rjmp TXCexit
out UDR, symb
TXCexit: reti

USART_RXC:
sbis UCSRA, RXC
rjmp USART_RXC
; Get status and ninth bit, then data from buffer
in r16, UCSRA
in r17, UCSRB
; If error, return -1
andi r16,(1<<FE)|(1<<DOR)|(1<<PE)
breq USART_ReceiveNoError
in  r16, UDR
ldi r17, HIGH(-1)
ldi r16, LOW(-1)
reti
USART_ReceiveNoError:
; Filter the ninth bit, then return
in   r16, UDR
; - - - - - Choise to mode - - - - - - -
/*andi r16, 0x01
breq ch_int1
andi r16, 0x02
breq ch_int2
andi r16, 0x03
breq rep
andi r16, 0x04
breq ch_str1
andi r16, 0x05
breq ch_str2
;- - - - - error
reti
;change int1:
ch_int1:
ldi Timer1_interval, r16
reti
;change int2:
ch_int2:
ldi Timer2_interval, r16
reti
;reboot timers:
rep:
	ldi r17, 0b00000000	;bit: COM1A1 COM1A0 COM1B1 COM1B0 FOC1A FOC1B WGM11 WGM10
	out TCCR1A, r16
	ldi r17, 0b00000001 ;1<<CS00|1<<CS01 ; prescaler 64  
	out TCCR1B, r16
	ldi r17, 0b00000001 ; prescaler 64 CS12(1) 00000111(1024)
	out TCCR2, r16
reti
;change str1:
ch_str1:

reti
;change str2:
ch_str2:
reti*/

Timer1_STR: .DB "ping!"
Timer2_STR: .DB "pong!"
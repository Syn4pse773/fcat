; FCAT

format	ELF64 executable 3
entry	start

; SYSCALL NUMBERS
sys_read	= 0
sys_write	= 1
sys_open	= 2
sys_close	= 3
sys_exit	= 60


segment	readable executable

	start:
		; INIT
		mov	rax, [rsp]
		mov	[argc_val], rax
		lea	rax, [rsp+8]
		mov	[argv_val], rax

		mov	byte[line_start], 1
		mov	dword[consecutive_newlines], 0
		mov	qword[line_counter], 1
		mov	qword[out_ptr], out_buffer
		mov	byte[exit_status], 0



		; PARSE ARGS
		mov	rbx, 1
		.parse_args:
		mov	r8, [argc_val]
		cmp	rbx, r8
		jge	.done_parsing

		mov	r9, [argv_val]
		mov	rsi, [r9+rbx*8]

		cmp	byte[endopts], 0
		jne	.next_arg		; AFTER "--" ALL ARE FILES

		cmp	byte[rsi], '-'
		jne	.next_arg
		cmp	byte[rsi+1], 0
		je	.next_arg		; LONE "-" IS STDIN

		cmp	byte[rsi+1], '-'
		jne	.do_flags
		cmp	byte[rsi+2], 0
		jne	.do_flags		; "--foo" -> FLAG GROUP (WILL ERROR)
		mov	byte[endopts], 1	; EXACTLY "--"
		jmp	.next_arg

		.do_flags:
		inc	rsi
		.parse_flag_chars:
		mov	al, [rsi]
		test	al, al
		jz	.next_arg

		cmp	al, 'n'
		je	.set_opt_number
		cmp	al, 'E'
		je	.set_opt_ends
		cmp	al, 's'
		je	.set_opt_squeeze

		jmp	.invalid_option

		.set_opt_number:
		mov	byte[opt_number], 1
		jmp	.next_flag_char
		.set_opt_ends:
		mov	byte[opt_ends], 1
		jmp	.next_flag_char
		.set_opt_squeeze:
		mov	byte[opt_squeeze], 1
		jmp	.next_flag_char

		.next_flag_char:
		inc	rsi
		jmp	.parse_flag_chars

		.next_arg:
		inc	rbx
		jmp	.parse_args



		; PROCESS FILES
		.done_parsing:
		mov	byte[endopts], 0	; RESET FOR SECOND PASS
		mov	rbx, 1
		mov	dword[file_count], 0
		.process_args:
		mov	r8, [argc_val]
		cmp	rbx, r8
		jge	.done_processing

		mov	r9, [argv_val]
		mov	rsi, [r9+rbx*8]

		cmp	byte[endopts], 0
		jne	.process_file

		cmp	byte[rsi], '-'
		jne	.process_file
		cmp	byte[rsi+1], 0
		je	.process_file		; LONE "-" -> STDIN

		cmp	byte[rsi+1], '-'
		jne	.next_process_arg
		cmp	byte[rsi+2], 0
		jne	.next_process_arg
		mov	byte[endopts], 1	; "--"
		jmp	.next_process_arg

		.process_file:
		inc	dword[file_count]
		call	process_one_file

		.next_process_arg:
		inc	rbx
		jmp	.process_args



		; STDIN FALLBACK
		.done_processing:
		cmp	dword[file_count], 0
		jne	.exit_program

		mov	rsi, stdin_name
		call	process_one_file

		; EXIT
		.exit_program:
		call	flush_outbuf
		movzx	rdi, byte[exit_status]
		mov	rax, sys_exit
		syscall

		.invalid_option:
		mov	rax, sys_write
		mov	rdi, 2
		mov	rsi, err_opt
		mov	rdx, err_opt_len
		syscall
		mov	rax, sys_exit
		mov	rdi, 1
		syscall




	; rsi = filename
	process_one_file:
		mov	r13, rsi

		; "-" ? STDIN
		cmp	byte[r13], '-'
		jne	.open_regular
		cmp	byte[r13+1], 0
		jne	.open_regular

		mov	r12, 0
		jmp	.read_file_loop

		.open_regular:
		mov	rax, sys_open
		mov	rdi, r13
		xor	rsi, rsi		; O_RDONLY
		xor	rdx, rdx
		syscall
		cmp	rax, 0
		jl	.open_error
		mov	r12, rax

		.read_file_loop:
		mov	rax, sys_read
		mov	rdi, r12
		mov	rsi, in_buffer
		mov	rdx, 4096
		syscall
		test	rax, rax
		jz	.file_done
		jns	.read_ok
		cmp	rax, -4			; EINTR ? RETRY
		je	.read_file_loop
		jmp	.read_error

		.read_ok:
		mov	r14, rax		; count
		mov	r15, in_buffer		; ptr
		call	process_buffer
		jmp	.read_file_loop

		.file_done:
		cmp	r12, 0
		je	.return

		mov	rax, sys_close
		mov	rdi, r12
		syscall
		.return:
		ret

		; OPEN ERROR -> errno
		.open_error:
		neg	rax
		cmp	rax, 2			; ENOENT
		je	.oe_noent
		cmp	rax, 13			; EACCES
		je	.oe_acces
		cmp	rax, 21			; EISDIR
		je	.oe_isdir
		lea	rsi, [err_generic]
		mov	rdx, err_generic_len
		jmp	.oe_emit
		.oe_noent:
		lea	rsi, [err_noent]
		mov	rdx, err_noent_len
		jmp	.oe_emit
		.oe_acces:
		lea	rsi, [err_acces]
		mov	rdx, err_acces_len
		jmp	.oe_emit
		.oe_isdir:
		lea	rsi, [err_isdir]
		mov	rdx, err_isdir_len
		.oe_emit:
		call	print_file_error
		ret

		.read_error:
		neg	rax
		cmp	rax, 21			; EISDIR
		je	.re_isdir
		lea	rsi, [err_readio]
		mov	rdx, err_readio_len
		jmp	.re_emit
		.re_isdir:
		lea	rsi, [err_isdir]
		mov	rdx, err_isdir_len
		.re_emit:
		call	print_file_error
		jmp	.file_done




	; r13 = filename
	; rsi = msg
	; rdx = len
	; -> "fcat: <file>: <msg>", exit_status = 1
	print_file_error:
		push	rsi
		push	rdx

		mov	rax, sys_write
		mov	rdi, 2
		mov	rsi, err_prefix
		mov	rdx, err_prefix_len
		syscall

		; rcx = strlen(filename)
		xor	rcx, rcx
		@@:
		cmp	byte[r13+rcx], 0
		je	@f
		inc	rcx
		jmp	@b
		@@:
		mov	rax, sys_write
		mov	rdi, 2
		mov	rsi, r13
		mov	rdx, rcx
		syscall

		mov	rax, sys_write
		mov	rdi, 2
		mov	rsi, err_colon
		mov	rdx, err_colon_len
		syscall

		pop	rdx
		pop	rsi
		mov	rax, sys_write
		mov	rdi, 2
		syscall

		mov	byte[exit_status], 1
		ret




	; r15 = buffer, r14 = count
	process_buffer:
		; FAST PATH: NO FLAGS
		cmp	byte[opt_number], 0
		jne	.process_formatted
		cmp	byte[opt_ends], 0
		jne	.process_formatted
		cmp	byte[opt_squeeze], 0
		jne	.process_formatted

		mov	rsi, r15
		mov	rdx, r14
		call	write_passthrough
		ret

		.process_formatted:
		test	r14, r14
		jz	.formatted_done

		movzx	rax, byte[r15]
		cmp	al, 10
		je	.char_newline

		mov	dword[consecutive_newlines], 0

		cmp	byte[line_start], 1
		jne	.print_char

		cmp	byte[opt_number], 0
		je	.after_line_number
		call	print_line_number
		.after_line_number:
		mov	byte[line_start], 0

		.print_char:
		mov	rsi, r15
		mov	rdx, 1
		call	write_to_outbuf

		.next_char:
		inc	r15
		dec	r14
		jmp	.process_formatted

		.formatted_done:
		ret

		; NEWLINE
		.char_newline:
		cmp	byte[opt_squeeze], 0
		je	.no_squeeze

		cmp	byte[line_start], 1
		jne	.reset_squeeze_counter

		inc	dword[consecutive_newlines]
		cmp	dword[consecutive_newlines], 2
		jge	.skip_empty_line	; SQUEEZE

		cmp	byte[opt_number], 0
		je	.print_squeezed_newline
		call	print_line_number
		jmp	.print_squeezed_newline

		.reset_squeeze_counter:
		mov	dword[consecutive_newlines], 0
		jmp	.no_squeeze

		.no_squeeze:
		cmp	byte[line_start], 1
		jne	.print_ends
		cmp	byte[opt_number], 0
		je	.print_ends
		call	print_line_number

		.print_ends:
		cmp	byte[opt_ends], 0
		je	.print_newline_char

		push	r15
		mov	byte[temp_char], '$'
		mov	rsi, temp_char
		mov	rdx, 1
		call	write_to_outbuf
		pop	r15

		.print_newline_char:
		mov	rsi, r15
		mov	rdx, 1
		call	write_to_outbuf

		mov	byte[line_start], 1
		jmp	.next_char

		.print_squeezed_newline:
		jmp	.print_ends
		.skip_empty_line:
		jmp	.next_char




	; WRITE line_counter, TAB. MIN WIDTH 6, GROWS
	print_line_number:
		push	rax
		push	rbx
		push	rcx
		push	rdx
		push	rdi
		push	rsi

		lea	rdi, [line_num_buf+line_num_buf_size-1]
		mov	byte[rdi], 9		; TAB
		mov	rax, [line_counter]
		mov	rbx, 10
		xor	rcx, rcx		; digit count
		@@:
		dec	rdi
		xor	rdx, rdx
		div	rbx
		add	dl, '0'
		mov	[rdi], dl
		inc	rcx
		test	rax, rax
		jnz	@b

		; PAD TO MIN WIDTH 6
		@@:
		cmp	rcx, 6
		jge	@f
		dec	rdi
		mov	byte[rdi], 32
		inc	rcx
		jmp	@b
		@@:
		inc	qword[line_counter]

		mov	rsi, rdi
		lea	rdx, [line_num_buf+line_num_buf_size]
		sub	rdx, rdi
		call	write_to_outbuf

		pop	rsi
		pop	rdi
		pop	rdx
		pop	rcx
		pop	rbx
		pop	rax
		ret




	; rsi = data, rdx = len. BLOCK COPY INTO out_buffer
	write_to_outbuf:
		push	rdi
		push	rsi
		push	rcx

		mov	rdi, [out_ptr]
		.loop:
		test	rdx, rdx
		jz	.done

		; SPACE LEFT = (out_buffer+4096) - rdi
		lea	rax, [out_buffer+4096]
		sub	rax, rdi
		jnz	.have_space

		; FULL ? FLUSH
		push	rsi
		push	rdx
		call	flush_outbuf_rdi
		pop	rdx
		pop	rsi
		mov	rdi, out_buffer
		mov	rax, 4096

		.have_space:
		; CHUNK = min(rdx, space_left)
		mov	rcx, rdx
		cmp	rcx, rax
		jbe	@f
		mov	rcx, rax
		@@:
		sub	rdx, rcx
		rep	movsb
		jmp	.loop

		.done:
		mov	[out_ptr], rdi
		pop	rcx
		pop	rsi
		pop	rdi
		ret



	; rsi = data, rdx = len. PASSTHROUGH: FLUSH BUFFER, WRITE DIRECT TO STDOUT
	write_passthrough:
		push	rsi
		push	rdx
		mov	rdi, [out_ptr]
		call	flush_outbuf_rdi
		pop	rdx
		pop	rsi
		call	write_all
		ret



	flush_outbuf:
		push	rdi
		mov	rdi, [out_ptr]
		call	flush_outbuf_rdi
		pop	rdi
		ret



	; rdi = end ptr. FLUSH [out_buffer, rdi) TO STDOUT
	flush_outbuf_rdi:
		mov	rdx, rdi
		sub	rdx, out_buffer
		mov	rsi, out_buffer
		call	write_all
		mov	rdi, out_buffer
		mov	[out_ptr], rdi
		ret



	; rsi = buf, rdx = len. WRITE ALL TO STDOUT, RETRY SHORT/EINTR
	write_all:
		test	rdx, rdx
		jz	.done
		.wloop:
		mov	rax, sys_write
		mov	rdi, 1
		syscall
		test	rax, rax
		jg	.advance
		cmp	rax, -4			; EINTR ? RETRY
		je	.wloop
		jmp	.done			; OTHER ERROR / 0 ? GIVE UP
		.advance:
		add	rsi, rax
		sub	rdx, rax
		jnz	.wloop
		.done:
		ret


segment	readable writeable

	; STATE
	argc_val		dq	0
	argv_val		dq	0
	file_count		dd	0
	exit_status		db	0
	endopts			db	0

	; OPTIONS
	opt_number		db	0
	opt_ends		db	0
	opt_squeeze		db	0

	; FORMAT STATE
	line_start		db	1
	consecutive_newlines	dd	0
	line_counter		dq	1

	out_ptr			dq	0
	temp_char		db	0

	line_num_buf		rb	32
	line_num_buf_size	=	32


	; MESSAGES
	err_prefix		db	"fcat: "
	err_prefix_len		=	$ - err_prefix
	err_colon		db	": "
	err_colon_len		=	$ - err_colon
	err_noent		db	"No such file or directory", 10
	err_noent_len		=	$ - err_noent
	err_acces		db	"Permission denied", 10
	err_acces_len		=	$ - err_acces
	err_isdir		db	"Is a directory", 10
	err_isdir_len		=	$ - err_isdir
	err_readio		db	"Input/output error", 10
	err_readio_len		=	$ - err_readio
	err_generic		db	"Cannot open file", 10
	err_generic_len		=	$ - err_generic
	err_opt			db	"fcat: invalid option", 10, "Usage: fcat [-nEs] [file...]", 10
	err_opt_len		=	$ - err_opt
	stdin_name		db	"-", 0


	; BUFFERS
	in_buffer		rb	4096
	out_buffer		rb	4096

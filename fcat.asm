format ELF64 executable 3
entry start

include 'std.inc'

segment writeable executable

start:
	pop rcx
	cmp rcx, 2
	pop rdx
	pop rdi

	jl .noargs
	open rdi, 0, 0

	if_error_exit
	mov r12, 	rax
.read_loop:
	read r12, buffer, 512
	cmp rax, 	0
	jle .done	
	mov r13, 	rax

	write 1, buffer, r13 
	jmp .read_loop

.done:	
	write 1, newline, 1
	mov rax, sys_close
	mov rdi, r12
	syscall
	exit 0

.noargs:
	write 2, no_args_msg, no_args_len
	exit 1
segment readable writeable
	newline db 10
	no_args_msg db 'No arguments provided', 10
	no_args_len = $ - no_args_msg
	buffer rb 512
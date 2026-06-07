format ELF64 executable 3
entry start

segment writeable executable

start:
	pop rcx
	cmp rcx, 2
	pop rdx
	pop rdi

	jl .noargs

	mov rax, 2
	xor rsi, rsi
	xor rdx, rdx
	syscall

	cmp rax, 0
	jl .open_error
	mov r12, rax

.read_loop:
	mov rax, 0
	mov rdi, r12
	mov rsi, buffer
	mov rdx, 512
	syscall

	cmp rax, 0
	jle .done	
	mov r13, rax

	mov rax, 1
	mov rdi, 1
	mov rsi, buffer
	mov rdx, r13
	syscall
	jmp .read_loop

.done:	
	mov rax, 1
	mov rdi, 1
	mov rsi, newline
	mov rdx, 1
	syscall

	mov rax, 3
	mov rdi, r12
	syscall

	mov rax, 60
	xor rdi, rdi
	syscall

.noargs:
	mov rax, 1
	mov rdi, 2
	mov rsi, no_args_msg
	mov rdx, no_args_len
	syscall

	mov rax, 60
	mov rdi, 1
	syscall

.open_error:
	mov rax, 60
	mov rdi, 2
	syscall

segment readable writeable
	newline db 10
	no_args_msg db 'No arguments provided', 10
	no_args_len = $ - no_args_msg
	buffer rb 512

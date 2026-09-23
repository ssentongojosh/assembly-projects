.global _start

.intel_syntax noprefix
# You must know that on x86_64 architecture, return values are passed in the rax register
# The first six function arguments are passed in the registers rdi, rsi, rdx, r10, r8 and r9 in that order
# These are lables <any word>: which act as human readable placeholders for memory addresses. They can be used to define constants
# and also code reuse just like functions in high  level languages
# No direct memeory to memory mov is allowed therefore this fails: mov [rax], [rbx]
# You must use a temporary register to store the value such as mov rcx, [rbx] mov [rax], rcx
#
# word = 2 bytes
# long = 4 bytes
#
# directives begin with a dot such as .zero. They are not instructions. They simply direct teh assembler on how 
# to organize our data in memeory in preparation for communication
# for example .zero 8 tells the compiler to reserve 8 bytes and zero them out

_start:

    # Create socket
    # int socket(int domain, int type, int protocol) returns a file descriptor of the new socket
    # if successful, socket is created and exists in AF but has no address assigned to it

    mov rdi, 2               # domain = AF_INET (ipv4 internet protocols)

    mov rsi, 1               # type = SOCK_STREAM (TCP - two way and reliable) type defines the communication semantics

    mov rdx, 0               # protocol = IPPROTO_IP

    mov rax, 41              # socket syscall number

    syscall

    mov r15, rax             # store listening socket File Descriptor for use when calling listen


    # Bind socket to address
    # int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)

    mov rdi, r15             # sockfd = socket(...) whatever socket returned

    lea rsi, [rip + sockaddr_struct] # this is a relative address resolution returning address of the sockaddr_struct

    mov rdx, socklen_t       # socklen_t = socklen_t which 16 calculated via .equ directive

    mov rax, 49              # bind syscall

    syscall


    # Start listening 

    mov rax, 50              # listen syscall

    mov rdi, r15

    mov rsi, 0

    syscall


    jmp accept_loop


accept_loop:

    # Accept new client connection

    mov rax, 43              # accept syscall

    mov rdi, r15

    mov rsi, [rip + client_addr]

    mov rdx, [rip + addr_len]

    syscall

    mov r14, rax             # store client socket FD


    # Fork to handle client concurrently

    mov rax, 57              # fork syscall

    syscall


    cmp rax, 0

    je child_process

    jmp parent_process


parent_process:

    # Parent closes client socket and continues accepting

    mov rdi, r14

    mov rax, 3               # close syscall

    syscall

    jmp accept_loop


child_process:

    # Child closes listening socket

    mov rax, 3               # close syscall

    mov rdi, r15

    syscall


    # Read HTTP request from client

    mov rdi, r14

    lea rsi, [rip + http_request]

    mov rdx, 512

    mov rax, 0               # read syscall

    syscall

    mov r9, rax              # save bytes read


    # Determine request type

    cmp byte ptr [rip + http_request], 'G'

    je get_request

    cmp byte ptr [rip + http_request], 'P'

    je post_request


get_request:

    # Extract filename from GET request

    mov rax, 4               # skip "GET "

    mov r11, rax

    xor rdi, rdi

    jmp extract_filename


post_request:

    # Extract filename from POST request

    mov rax, 5               # skip "POST "

    mov r11, rax

    xor rdi, rdi

    jmp extract_filename


extract_filename:

    lea rbx, [rip + file]

    lea rdx, [rip + http_request]

    cmp byte ptr [rdx + rax], 0x20   # check for space

    je filename_extracted

    mov r10b, [rdx + rax]            # copy character

    mov [rbx + rdi], r10b

    inc rax

    inc rdi

    jmp extract_filename


filename_extracted:

    cmp r11, 4               # check if GET request

    je handle_get

    cmp r11, 5               # check if POST request

    je handle_post

handle_get:

    # Open file for reading

    lea rdi, [rip + file]

    mov rsi, 0               # O_RDONLY

    mov rdx, 0

    mov rax, 2               # open syscall

    syscall

    mov r12, rax


    # Read file content

    mov rdi, rax

    lea rsi, [rip + content]

    mov rdx, 256

    mov rax, 0               # read syscall

    syscall

    mov r13, rax             # save bytes read


    # Close file

    mov rdi, r12

    mov rax, 3               # close syscall

    syscall


    # Send HTTP response header

    mov rdi, r14

    lea rsi, [rip + http_response]

    mov rdx, 19

    mov rax, 1               # write syscall

    syscall


    # Send file content

    mov rdi, r14

    lea rsi, [rip + content]

    mov rdx, r13

    mov rax, 1               # write syscall

    syscall


    # Close client connection

    mov rdi, r14

    mov rax, 3               # close syscall

    syscall

    jmp exit_child


handle_post:

    # Open file for writing

    lea rdi, [rip + file]

    mov rsi, 0x41                    # O_WRONLY | O_CREAT

    mov rdx, 0x1FF                   # file permissions

    mov rax, 2                       # open syscall

    syscall

    mov r12, rax


    # Find end of HTTP headers (\r\n\r\n)

    xor rcx, rcx

    lea rdx, [rip + http_request]


find_headers_end:

    mov al, [rdx + rcx]

    cmp al, 0

    je headers_not_found


    # Check for \r\n\r\n sequence

    cmp al, 0x0d

    jne next_header_char


    mov al, [rdx + rcx + 1]

    cmp al, 0x0a

    jne next_header_char


    mov al, [rdx + rcx + 2]

    cmp al, 0x0d

    jne next_header_char


    mov al, [rdx + rcx + 3]

    cmp al, 0x0a

    je headers_found


next_header_char:

    inc rcx

    jmp find_headers_end


headers_found:

    add rcx, 4                       # skip past \r\n\r\n

    mov rax, r9

    sub r9, rcx                      # calculate content length

    mov r8, rcx

    jmp write_content


headers_not_found:

    # Treat entire request as content

    mov r8, 0

    jmp write_content


write_content:

    mov rdi, r12

    lea rsi, [rip + http_request]

    add rsi, r8                      # skip headers

    mov rdx, r9                      # content length

    mov rax, 1                       # write syscall

    syscall


    # Close file

    mov rdi, r12

    mov rax, 3                       # close syscall

    syscall


    # Send response

    mov rdi, r14

    lea rsi, [rip + http_response]

    mov rdx, 19

    mov rax, 1                       # write syscall

    syscall


    jmp exit_child


exit_child:

    mov rdi, 0

    mov rax, 60                      # exit syscall

    syscall


# Data structures
#
# struct sockaddr  {
# sa_family_t sa_family;
# char        sa_data[14];
# }

sockaddr_struct:

    .word 2                          # sin_family =  AF_INET (ipv4)

    .word 0x901F                     # sin_port =  8080 (big endian/ network byte order)

    .long 0                          # sin_addr = INADDR_ANY (which is (in_addr_t) 0x00000000 ) or simply 0.0.0.0

    .zero 8                          # sin_zero = 0
.equ socklen_t, . - sockaddr_struct  # calculate length of this sockaddr structure

client_addr:

    .zero 16


addr_len:

    .zero 16


.section .bss

http_request:

    .skip 512


content:

    .skip 256


file:

    .skip 24


.section .data

http_response:

    .string "HTTP/1.0 200 OK\r\n\r\n"

.section .text
.global switchCtx
.global initCall
.align  2
# rcx: cur_ctx_ptr
# rdx: next_ctx_ptr
switchCtx:
    # save cur context
    movq %rbx,  0(%rcx)      # save rbx
    movq %r12,  8(%rcx)      # save r12
    movq %r13, 16(%rcx)      # save r13
    movq %r14, 24(%rcx)      # save r14
    movq %r15, 32(%rcx)      # save r15
    movq %rdi, 40(%rcx)      # save rdi
    movq %rsi, 48(%rcx)      # save rsi
    movq %rsp, 56(%rcx)      # save rsp
    movq %rbp, 64(%rcx)      # save rbp
    movups %xmm6, 80(%rcx)   # save xmm6
    movups %xmm7, 96(%rcx)   # save xmm7
    movups %xmm8, 112(%rcx)  # save xmm8
    movups %xmm9, 128(%rcx)  # save xmm9
    movups %xmm10, 144(%rcx) # save xmm10
    movups %xmm11, 160(%rcx) # save xmm11
    movups %xmm12, 176(%rcx) # save xmm12
    movups %xmm13, 192(%rcx) # save xmm13
    movups %xmm14, 208(%rcx) # save xmm14
    movups %xmm15, 224(%rcx) # save xmm15
    # for saving rip to addr of `.return`
    leaq .switch_ctx_to_return(%rip), %rax
    movq %rax, 72(%rcx)

    # load next context
    movq  0(%rdx), %rbx      # load rbx
    movq  8(%rdx), %r12      # load r12
    movq 16(%rdx), %r13      # load r13
    movq 24(%rdx), %r14      # load r14
    movq 32(%rdx), %r15      # load r15
    movq 40(%rdx), %rdi      # load rdi
    movq 48(%rdx), %rsi      # load rsi
    movq 56(%rdx), %rsp      # load rsp
    movq 64(%rdx), %rbp      # load rbp
    movups 80(%rdx), %xmm6   # load xmm6
    movups 96(%rdx), %xmm7   # load xmm7
    movups 112(%rdx), %xmm8  # load xmm8
    movups 128(%rdx), %xmm9  # load xmm9
    movups 144(%rdx), %xmm10 # load xmm10
    movups 160(%rdx), %xmm11 # load xmm11
    movups 176(%rdx), %xmm12 # load xmm12
    movups 192(%rdx), %xmm13 # load xmm13
    movups 208(%rdx), %xmm14 # load xmm14
    movups 224(%rdx), %xmm15 # load xmm15
    pushq 72(%rdx)           # load rip
.switch_ctx_to_return:
    ret

# rcx: args_ptr
# rdx: typeSafeCall function address
initCall:
    push %rcx # save args_ptr
    push %rdx # save func addr
    call mainCtxPtr
    push %rax # save main ctx ptr
    call currentCtxPtr
    popq %r8  # load main ctx ptr
    popq %rdx # load func addr
    popq %rcx # load args_ptr

    # now r8  = main_ctx
    #     rax = cur_ctx
    # save main ctx
    movq %rbx,  0(%r8)      # save rbx
    movq %r12,  8(%r8)      # save r12
    movq %r13, 16(%r8)      # save r13
    movq %r14, 24(%r8)      # save r14
    movq %r15, 32(%r8)      # save r15
    movq %rdi, 40(%r8)      # save rdi
    movq %rsi, 48(%r8)      # save rsi
    movq %rsp, 56(%r8)      # save rsp
    movq %rbp, 64(%r8)      # save rbp
    movups %xmm6, 80(%r8)   # save xmm6
    movups %xmm7, 96(%r8)   # save xmm7
    movups %xmm8, 112(%r8)  # save xmm8
    movups %xmm9, 128(%r8)  # save xmm9
    movups %xmm10, 144(%r8) # save xmm10
    movups %xmm11, 160(%r8) # save xmm11
    movups %xmm12, 176(%r8) # save xmm12
    movups %xmm13, 192(%r8) # save xmm13
    movups %xmm14, 208(%r8) # save xmm14
    movups %xmm15, 224(%r8) # save xmm15
    # for saving rip to addr of `.return`
    leaq .switch_ctx_to_return(%rip), %rbx
    movq %rbx, 72(%r8)

    # load coroutine stack
    movq 56(%rax), %rsp
    movq %rsp, %rbp 
    
    # call typeSafeCall function
    call *%rdx

.init_call_to_return:
    ret
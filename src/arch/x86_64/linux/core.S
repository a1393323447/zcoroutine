.section .text
.global switchCtx
.global switchToNext
.global initCall
.align  2
# rdi: cur_ctx_ptr
# rsi: next_ctx_ptr
switchCtx:
    # save current context
    movq %rbx,  0(%rdi)     # save rbx
    movq %r12,  8(%rdi)     # save r12
    movq %r13, 16(%rdi)     # save r13
    movq %r14, 24(%rdi)     # save r14
    movq %r15, 32(%rdi)     # save r15
    movq %rsp, 40(%rdi)     # save rsp
    movq %rbp, 48(%rdi)     # save rbp
    # for saving rip to addr of `.return`
    leaq .switch_ctx_to_return(%rip), %rax
    movq %rax, 56(%rdi)

    # load next context
    movq   0(%rsi), %rbx     # load rbx
    movq   8(%rsi), %r12     # load r12
    movq  16(%rsi), %r13     # load r13
    movq  24(%rsi), %r14     # load r14
    movq  32(%rsi), %r15     # load r15
    movq  40(%rsi), %rsp     # load rsp
    movq  48(%rsi), %rbp     # load rbp
    pushq 56(%rsi)           # load rip
.switch_ctx_to_return:
    ret

# rdi: next_ctx_ptr
switchToNext:
    # load next context
    movq   0(%rdi), %rbx     # load rbx
    movq   8(%rdi), %r12     # load r12
    movq  16(%rdi), %r13     # load r13
    movq  24(%rdi), %r14     # load r14
    movq  32(%rdi), %r15     # load r15
    movq  40(%rdi), %rsp     # load rsp
    movq  48(%rdi), %rbp     # load rbp
    pushq 56(%rdi)           # load rip
    ret

# rdi: args_ptr
# rsi: typeSafeCall function address
# rdx: curr_ctx_ptr
# rcx: next_ctx_ptr
initCall:
    # save curr ctx
    movq %rbx,  0(%rdx)    # save rbx
    movq %r12,  8(%rdx)    # save r12
    movq %r13, 16(%rdx)    # save r13
    movq %r14, 24(%rdx)    # save r14
    movq %r15, 32(%rdx)    # save r15
    movq %rsp, 40(%rdx)    # save rsp
    movq %rbp, 48(%rdx)    # save rbp
    # for saving rip to addr of `.return`
    leaq .init_call_to_return(%rip), %rbx
    movq %rbx, 56(%rdx)

    # load coroutine stack
    movq 40(%rcx), %rsp
    
    # call typeSafeCall function
    call *%rsi

.init_call_to_return:
    ret
module nlopt_user_func_mod

    use, intrinsic :: iso_c_binding, only: c_double, c_int
    implicit none
    private

    public :: nlopt_user_func
    public :: nlopt_user_mfunc
    public :: nlopt_user_precond

    !
    ! these types are to be extended by the user
    !

    type, abstract :: nlopt_user_func
    contains
        procedure(nlopt_func_if), deferred, public :: eval
    end type

    type, abstract :: nlopt_user_mfunc
    contains
        procedure(nlopt_mfunc_if), deferred, public :: eval
    end type

    type, abstract :: nlopt_user_precond
    contains
        procedure(nlopt_precond_if), deferred, public :: eval
    end type


    abstract interface
        real(c_double) function nlopt_func_if(this,n,x,grad)
            import nlopt_user_func, c_double, c_int
            class(nlopt_user_func), intent(in) :: this
            integer(c_int), intent(in) :: n
            real(c_double), intent(in) :: x(n)
            real(c_double), intent(out), optional :: grad(n)
        end function
        subroutine nlopt_mfunc_if(this,m,result,n,x,grad)
            import nlopt_user_mfunc, c_double, c_int
            class(nlopt_user_mfunc), intent(in) :: this
            integer(c_int), intent(in) :: m
            real(c_double), intent(out) :: result(m)
            integer(c_int), intent(in) :: n
            real(c_double), intent(in) :: x(n)
            real(c_double), intent(out), optional :: grad(m,n)
        end subroutine
        subroutine nlopt_precond_if(this,n,x,v,vpre)
            import nlopt_user_precond, c_double, c_int
            class(nlopt_user_precond), intent(in) :: this
            integer(c_int), intent(in) :: n
            real(c_double), intent(in) :: x(n)
            real(c_double), intent(in) :: v(n)
            real(c_double), intent(out) :: vpre(n)
        end subroutine
    end interface

end module

module adaptor_mod

    use iso_c_binding
    use nlopt_user_func_mod
    implicit none
    private

    public :: adaptor, func_aux, mfunc_aux, precond_aux

    type :: adaptor
        class(nlopt_user_func), pointer :: f => null()
        class(nlopt_user_mfunc), pointer :: mf => null()
        class(nlopt_user_precond), pointer :: pre => null()
    end type

contains

    real(c_double) function func_aux(n,x,grad,data)
        integer(c_int), intent(in), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(out), optional :: grad(n)
        type(c_ptr), value :: data
        
        type(adaptor), pointer :: fdata
        call c_f_pointer(data,fdata) ! fdata contains both callback and data
        
        func_aux = fdata%f%eval(n,x,grad)
    end function

    subroutine mfunc_aux(m,result,n,x,grad,data)
        integer(c_int), intent(in), value :: m
        real(c_double), intent(out) :: result(m)
        integer(c_int), intent(in), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(out), optional :: grad(m,n)
        type(c_ptr), value :: data
        
        type(adaptor), pointer :: fdata
        call c_f_pointer(data,fdata) ! fdata contains both callback and data

        call fdata%mf%eval(m,result,n,x,grad)
    end subroutine

    subroutine precond_aux(n,x,v,vpre,data)
        integer(c_int), intent(in), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(in) :: v(n)
        real(c_double), intent(out) :: vpre(n)
        type(c_ptr), value :: data
        
        type(adaptor), pointer :: fdata
        call c_f_pointer(data,fdata) ! fdata contains both callback and data

        call fdata%pre%eval(n,x,v,vpre)
    end subroutine

end module

module nlopt

    use, intrinsic :: iso_c_binding
    use nlopt_enum
    use nlopt_c_interface, srand => nlopt_srand, srand_time => nlopt_srand_time, &
    func => nlopt_func, mfunc => nlopt_mfunc, version => nlopt_version

    use nlopt_user_func_mod
    use adaptor_mod

    use handler_mod

    implicit none
    private

    public :: opt, new_opt, copy_opt
    public :: version, version_major, version_minor, version_bugfix
    public :: srand, srand_time, algorithm_name

    ! Expose abstract types in order for the user to extend them!
    public :: nlopt_user_func, nlopt_user_mfunc, nlopt_user_precond


    type :: handler
        private
        character(len=200) :: info = ''
        character(len=200) :: object_name = 'anonymous'
    contains
        procedure, non_overridable :: throw
        procedure, non_overridable :: set_info
    end type

    type :: opt
        private
        type(c_ptr) :: o = c_null_ptr ! the "nlopt_opt" object
        integer(c_int) :: last_result = NLOPT_FAILURE
        real(c_double) :: last_optf = huge(1._c_double)
        integer(c_int) :: forced_stop_reason = NLOPT_FORCED_STOP

        integer(c_int) :: n = 0 ! remember dimension for convenience

        type(handler), pointer, public :: h => null()
    contains

        procedure, public :: optimize

        procedure, public :: last_optimize_result
        procedure, public :: last_optimum_value

        procedure, public :: get_algorithm
        procedure, public :: get_algorithm_name
        procedure, public :: get_dimension

        procedure, private :: set_min_objective_classic
        procedure, private :: set_min_objective_oo
        generic, public :: set_min_objective => set_min_objective_classic, set_min_objective_oo

        procedure, private :: set_max_objective_classic
        procedure, private :: set_max_objective_oo
        generic, public :: set_max_objective => set_max_objective_classic, set_max_objective_oo

        procedure, public :: remove_inequality_constraints
        procedure, private :: add_inequality_constraint_classic
        procedure, private :: add_inequality_mconstraint_classic
        procedure, private :: add_inequality_constraint_oo
        procedure, private :: add_inequality_mconstraint_oo
        generic, public :: add_inequality_constraint => add_inequality_constraint_classic, add_inequality_constraint_oo

        procedure, public :: remove_equality_constraints
        procedure, public :: add_equality_constraint_cptr
        procedure, public :: add_equality_mconstraint_cptr
        procedure, public :: add_equality_constraint_oo
        procedure, public :: add_equality_mconstraint_oo
        generic, public :: add_equality_constraint => add_equality_constraint_cptr, add_equality_constraint_oo

        procedure, private :: set_lower_bounds_array
        procedure, private :: set_lower_bounds_scalar
        generic, public :: set_lower_bounds => set_lower_bounds_array, set_lower_bounds_scalar
        procedure, public :: get_lower_bounds

        procedure, private :: set_upper_bounds_array
        procedure, private :: set_upper_bounds_scalar
        generic, public :: set_upper_bounds => set_upper_bounds_array, set_upper_bounds_scalar
        procedure, public :: get_upper_bounds
        
        ! stopping criteria
        procedure, public :: set_stopval
        procedure, public :: get_stopval
        procedure, public :: set_ftol_rel
        procedure, public :: get_ftol_rel
        procedure, public :: set_ftol_abs
        procedure, public :: get_ftol_abs
        procedure, public :: set_xtol_rel
        procedure, public :: get_xtol_rel
        procedure, public :: set_xtol_abs
        procedure, public :: get_xtol_abs

        procedure, public :: set_maxeval
        procedure, public :: get_maxeval

        procedure, public :: get_numevals

        procedure, public :: set_maxtime
        procedure, public :: get_maxtime

        procedure, public :: set_force_stop
        procedure, public :: get_force_stop
        procedure, public :: force_stop

        procedure, public :: get_errmsg

        !
        ! more algorithm-specific parameters
        !
        procedure, public :: set_local_optimizer

        procedure, public :: set_population
        procedure, public :: get_population

        procedure, public :: set_vector_storage
        procedure, public :: get_vector_storage

        procedure, public :: set_default_initial_step
        procedure, private :: set_initial_step_array
        procedure, private :: set_initial_step_scalar
        generic, public :: set_initial_step => set_initial_step_array, set_initial_step_scalar
        procedure, public :: get_initial_step

        ! Overload assignment
        procedure, private :: assign_opt
        generic, public :: assignment(=) => assign_opt

        ! Destructor
        final :: destroy
    end type opt

    ! Constructors
    interface opt
        module procedure new_opt
        module procedure copy_opt
    end interface

    interface copy
        module procedure copy_opt
    end interface

contains

    function setup_handler(object_name) result(h)
        character(len=*), intent(in), optional :: object_name
        type(handler), pointer :: h
        
        allocate(h)
        if (present(object_name)) h%object_name(:) = object_name
        print *, "handler setup", associated(h)
    end function


    subroutine throw(my_handler,msg)
        class(handler), intent(in) :: my_handler
        character(len=*), intent(in), optional :: msg
        write(*,'("nlopt::throw on object ",A)') trim(my_handler%object_name)
        if (present(msg)) then
            write(*,'("   with message ***",A,"***")') trim(msg)
        end if
    end subroutine

    subroutine set_info(my_handler,info)
        class(handler), intent(inout) :: my_handler
        character(len=*), intent(in) :: info
        my_handler%info = info
    end subroutine

    subroutine mythrow(this,ret)
        class(opt), intent(in) :: this
        integer(c_int), intent(in) :: ret

        character(len=:,kind=c_char), allocatable :: errmsg

        select case(ret)
        case(NLOPT_FAILURE)
            if (this%get_errmsg(errmsg)) then
                call this%h%throw(errmsg)
            else
                call this%h%throw("nlopt failure")
            end if
            stop 0
        case(NLOPT_OUT_OF_MEMORY)
            call this%h%throw("nlopt bad alloc")
            stop 0
        case(NLOPT_INVALID_ARGS)
            if (this%get_errmsg(errmsg)) then
                if (allocated(errmsg)) call this%h%throw(errmsg)
            else
                call this%h%throw("nlopt invalid argument")
            end if
            stop 0
        case(NLOPT_ROUNDOFF_LIMITED)
            call this%h%throw("nlopt roundoff-limited")
            stop 0
        case(NLOPT_FORCED_STOP)
            call this%h%throw("nlopt forced stop")
            stop 0
        case default
            return
        end select
    end subroutine


    type(opt) function new_opt(a,n,object_name)
        integer(c_int), intent(in) :: a
        integer(c_int), intent(in) :: n
        character(len=*), intent(in), optional :: object_name
        new_opt%o = nlopt_create(a,n)
        new_opt%last_result = NLOPT_FAILURE
        new_opt%last_optf = huge(new_opt%last_optf)
        new_opt%forced_stop_reason = NLOPT_FORCED_STOP

        allocate(new_opt%h)
        if (present(object_name)) new_opt%h => setup_handler(object_name)
    end function

    ! Copy constructor
    type(opt) function copy_opt(f)
        type(opt), intent(in) :: f
        copy_opt%o = nlopt_copy(f%o)
        copy_opt%last_result = f%last_result
        copy_opt%last_optf = f%last_optf
        copy_opt%forced_stop_reason = f%forced_stop_reason
        allocate(copy_opt%h,source=f%h)
    end function

    ! Assignment
    subroutine assign_opt(lhs,rhs)
        class(opt), intent(inout) :: lhs
        class(opt), intent(in) :: rhs
        if (c_associated(lhs%o,rhs%o)) return ! self-assignment
        call nlopt_destroy(lhs%o)
        nullify(lhs%h)

        lhs%o = nlopt_copy(rhs%o)
        lhs%last_result = rhs%last_result
        lhs%last_optf = rhs%last_optf
        lhs%forced_stop_reason = rhs%forced_stop_reason
        lhs%h => rhs%h
    end subroutine

    ! Finalizer/destructor
    subroutine destroy(this)
        type(opt), intent(inout) :: this
        call nlopt_destroy(this%o)
    end subroutine

    ! Do the optimization
    integer(c_int) function optimize(this,x,opt_f)
        class(opt), intent(inout) :: this
        real(c_double), intent(inout) :: x(get_dimension(this))
        real(c_double), intent(inout) :: opt_f
        integer(c_int) :: ret
        
        this%forced_stop_reason = NLOPT_FORCED_STOP
        ret = nlopt_optimize(this%o,x,opt_f)
        this%last_result = ret
        this%last_optf = opt_f
        ! if (ret == NLOPT_FORCED_STOP) call mythrow(this%forced_stop_reason)
        ! call mythrow(ret)
        optimize = ret
    end function


    pure integer(c_int) function last_optimize_result(this)
        class(opt), intent(in) :: this
        last_optimize_result = this%last_result
    end function
    pure real(c_double) function last_optimum_value(this)
        class(opt), intent(in) :: this
        last_optimum_value = this%last_optf
    end function

    !
    ! Accessors
    !

    integer(c_int) function get_algorithm(this)
        class(opt), intent(in) :: this
        get_algorithm = nlopt_get_algorithm(this%o)
    end function
    function get_algorithm_name(this) result(name)
        class(opt), intent(in) :: this
        character(len=:,kind=c_char), allocatable :: name
        name = algorithm_name(this%get_algorithm())
    end function
    pure integer(c_int) function get_dimension(this)
        class(opt), intent(in) :: this
        get_dimension = nlopt_get_dimension(this%o)
    end function

    !
    ! Set the objective function
    !
    subroutine set_min_objective_classic(this,f,f_data)
        class(opt), intent(inout) :: this
        procedure(func) :: f
        type(c_ptr), intent(in) :: f_data
        integer(c_int) :: ret
        ret = nlopt_set_min_objective(this%o,c_funloc(f),f_data)
        ! call mythrow(ret)
    end subroutine
    subroutine set_max_objective_classic(this,f,f_data)
        class(opt), intent(inout) :: this
        procedure(func) :: f
        type(c_ptr), intent(in) :: f_data
        integer(c_int) :: ret
        ret = nlopt_set_max_objective(this%o,c_funloc(f),f_data)
        ! call mythrow(ret)
    end subroutine

    !
    ! Set the objective function (object-oriented way)
    !
    subroutine set_min_objective_oo(this,f)
        class(opt), intent(inout) :: this
        class(nlopt_user_func), intent(in), target :: f
        integer(c_int) :: ret

        type(adaptor), pointer :: data => null()
        allocate(data)
        data%f => f

        ret = nlopt_set_min_objective(this%o,c_funloc(func_aux),c_loc(data))
    end subroutine
    subroutine set_max_objective_oo(this,f)
        class(opt), intent(inout) :: this
        class(nlopt_user_func), intent(in), target :: f
        integer(c_int) :: ret

        type(adaptor), pointer :: data => null()
        allocate(data)
        data%f => f

        ret = nlopt_set_max_objective(this%o,c_funloc(func_aux),c_loc(data))
    end subroutine

    !
    ! Nonlinear constraints
    !
    subroutine remove_inequality_constraints(this,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_remove_equality_constraints(this%o)
        if (present(ires)) ires = ret
    end subroutine
    subroutine add_inequality_constraint_classic(this,fc,fc_data,tol,ires)
        class(opt), intent(inout) :: this
        procedure(func) :: fc
        type(c_ptr), value :: fc_data
        real(c_double), optional :: tol
        integer(c_int), intent(out), optional :: ires
        real(c_double) :: tol_
        integer(c_int) :: ret

        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol

        ret = nlopt_add_inequality_constraint(this%o,c_funloc(fc),fc_data,tol_)
        call mythrow(this,ret)
        if (present(ires)) ires = ret
    end subroutine
    subroutine add_inequality_mconstraint_classic(this,m,fc,fc_data,tol)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: m
        procedure(mfunc) :: fc
        type(c_ptr), value :: fc_data
        real(c_double), intent(in), optional :: tol(get_dimension(this))
        real(c_double) :: tol_(get_dimension(this))
        integer(c_int) :: ret

        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol
        
        ret = nlopt_add_inequality_mconstraint(this%o,m,c_funloc(fc),fc_data,tol_)
    end subroutine
    subroutine add_inequality_constraint_oo(this,fc,tol)
        class(opt), intent(inout) :: this
        class(nlopt_user_func), intent(in), target :: fc
        real(c_double), intent(in), optional :: tol
        real(c_double) :: tol_
        integer(c_int) :: ret
        type(adaptor), pointer :: fc_data => null()

        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol

        allocate(fc_data)
        fc_data%f => fc
        ret = nlopt_add_inequality_constraint(this%o,c_funloc(func_aux),c_loc(fc_data),tol_)
    end subroutine
    subroutine add_inequality_mconstraint_oo(this,m,fc,tol)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: m
        class(nlopt_user_mfunc), intent(in), target :: fc
        real(c_double), intent(in), optional :: tol(get_dimension(this))
        real(c_double) :: tol_(get_dimension(this))
        integer(c_int) :: ret
        type(adaptor), pointer :: fc_data => null()
        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol
        
        allocate(fc_data)
        fc_data%mf => fc
        ret = nlopt_add_inequality_mconstraint(this%o,m,c_funloc(mfunc_aux),c_loc(fc_data),tol_)
    end subroutine

    subroutine remove_equality_constraints(this,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_remove_inequality_constraints(this%o)
        if (present(ires)) ires = ret
    end subroutine
    subroutine add_equality_constraint_cptr(this,h,h_data,tol)
        class(opt), intent(inout) :: this
        procedure(func) :: h
        type(c_ptr), value :: h_data
        real(c_double), optional :: tol
        real(c_double) :: tol_
        integer(c_int) :: ret

        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol

        ret = nlopt_add_equality_constraint(this%o,c_funloc(h),h_data,tol_)
    end subroutine
    subroutine add_equality_mconstraint_cptr(this,m,h,h_data,tol)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: m
        procedure(mfunc) :: h
        type(c_ptr), value :: h_data
        real(c_double), optional :: tol(get_dimension(this))
        real(c_double) :: tol_(get_dimension(this))
        integer(c_int) :: ret

        tol_ = 0
        if (present(tol)) tol_ = tol

        ret = nlopt_add_equality_mconstraint(this%o,m,c_funloc(h),h_data,tol_)
    end subroutine
    subroutine add_equality_constraint_oo(this,h,tol)
        class(opt), intent(inout) :: this
        class(nlopt_user_func), intent(in), target :: h
        real(c_double), intent(in), optional :: tol
        real(c_double) :: tol_
        integer(c_int) :: ret
        type(adaptor), pointer :: h_data => null()

        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol

        allocate(h_data)
        h_data%f => h
        ret = nlopt_add_equality_constraint(this%o,c_funloc(func_aux),c_loc(h_data),tol_)
    end subroutine
    subroutine add_equality_mconstraint_oo(this,m,h,tol)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: m
        class(nlopt_user_mfunc), intent(in), target :: h
        real(c_double), intent(in), optional :: tol(get_dimension(this))
        real(c_double) :: tol_(get_dimension(this))
        integer(c_int) :: ret
        type(adaptor), pointer :: h_data => null()
        tol_ = 0.0_c_double
        if (present(tol)) tol_ = tol
        
        allocate(h_data)
        h_data%mf => h
        ret = nlopt_add_equality_mconstraint(this%o,m,c_funloc(mfunc_aux),c_loc(h_data),tol_)
    end subroutine

    subroutine set_lower_bounds_array(this,lb,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: lb(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_lower_bounds(this%o,lb)
        if (present(ires)) ires = ret
    end subroutine
    subroutine set_lower_bounds_scalar(this,lb,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: lb
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_lower_bounds1(this%o,lb)
        if (present(ires)) ires = ret
    end subroutine
    subroutine get_lower_bounds(this,lb,ires)
        class(opt), intent(in) :: this
        real(c_double), intent(out) :: lb(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_get_lower_bounds(this%o,lb)
        if (present(ires)) ires = ret
    end subroutine
    subroutine set_upper_bounds_array(this,ub,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: ub(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_upper_bounds(this%o,ub)
        if (present(ires)) ires = ret
    end subroutine
    subroutine set_upper_bounds_scalar(this,ub,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: ub
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_upper_bounds1(this%o,ub)
        if (present(ires)) ires = ret
    end subroutine
    subroutine get_upper_bounds(this,ub,ires)
        class(opt), intent(in) :: this
        real(c_double), intent(out) :: ub(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_get_upper_bounds(this%o,ub)
        if (present(ires)) ires = ret
    end subroutine


    real(c_double) function get_stopval(this)
        class(opt), intent(in) :: this
        get_stopval = nlopt_get_stopval(this%o)
    end function
    subroutine set_stopval(this,stopval,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: stopval
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_stopval(this%o,stopval)
        if (present(ires)) ires = ret
    end subroutine

    real(c_double) function get_ftol_rel(this)
        class(opt), intent(in) :: this
        get_ftol_rel = nlopt_get_ftol_rel(this%o)
    end function
    subroutine set_ftol_rel(this,tol,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: tol
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_ftol_rel(this%o,tol)
        if (present(ires)) ires = ret
    end subroutine

    real(c_double) function get_ftol_abs(this)
        class(opt), intent(in) :: this
        get_ftol_abs = nlopt_get_ftol_abs(this%o)
    end function
    subroutine set_ftol_abs(this,tol,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: tol
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_ftol_abs(this%o,tol)
        if (present(ires)) ires = ret
    end subroutine

    real(c_double) function get_xtol_rel(this)
        class(opt), intent(in) :: this
        get_xtol_rel = nlopt_get_xtol_rel(this%o)
    end function
    subroutine set_xtol_rel(this,tol,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: tol
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_xtol_rel(this%o,tol)
        if (present(ires)) ires = ret
    end subroutine
    subroutine set_xtol_abs(this,tol,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: tol(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_xtol_abs(this%o,tol)
        if (present(ires)) ires = ret
    end subroutine
    subroutine get_xtol_abs(this,tol,ires)
        class(opt), intent(in) :: this
        real(c_double), intent(out) :: tol(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_get_xtol_abs(this%o,tol)
        if (present(ires)) ires = ret
    end subroutine


    integer(c_int) function get_maxeval(this)
        class(opt), intent(in) :: this
        ! if (.not. associated(this%o)) 
        get_maxeval = nlopt_get_maxeval(this%o)
    end function
    subroutine set_maxeval(this,maxeval,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: maxeval
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_maxeval(this%o,maxeval)
        if (present(ires)) ires = ret
    end subroutine

    integer(c_int) function get_numevals(this)
        class(opt), intent(in) :: this
        get_numevals = nlopt_get_numevals(this%o)
    end function


    real(c_double) function get_maxtime(this)
        class(opt), intent(in) :: this
        get_maxtime = nlopt_get_maxtime(this%o)
    end function
    subroutine set_maxtime(this,maxtime,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: maxtime
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_maxtime(this%o,maxtime)
        if (present(ires)) ires = ret
    end subroutine

    integer(c_int) function get_force_stop(this)
        class(opt), intent(in) :: this
        ! if (.not. associated(this%o)) 
        get_force_stop = nlopt_get_force_stop(this%o)
    end function
    subroutine set_force_stop(this,ival,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: ival
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_force_stop(this%o,ival)
        if (present(ires)) ires = ret
    end subroutine
    subroutine force_stop(this)
        class(opt), intent(inout) :: this
        call this%set_force_stop(1_c_int)
    end subroutine


    logical function get_errmsg(this,errmsg)
        class(opt), intent(in) :: this
        character(len=:,kind=c_char), allocatable, intent(out), optional :: errmsg
        type(c_ptr) :: c_string
        character(len=1000,kind=c_char), pointer :: f_string
        
        c_string = nlopt_get_errmsg(this%o)
        if (.not. c_associated(c_string)) then
            get_errmsg = .false.
        else
            get_errmsg = .true.
            if (present(errmsg)) then
                call c_f_pointer(c_string,f_string)
                errmsg = f_string(1:index(f_string,c_null_char))
            end if
        end if
    end function

    subroutine set_local_optimizer(this,lo)
        class(opt), intent(inout) :: this
        class(opt), intent(in) :: lo
        integer(c_int) :: ret
        ret = nlopt_set_local_optimizer(this%o,lo%o)
        ! call mythrow(ret)
    end subroutine

    integer(c_int) function get_population(this)
        class(opt), intent(in) :: this
        get_population = nlopt_get_population(this%o)
    end function
    subroutine set_population(this,pop,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: pop
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_population(this%o,pop)
        if (present(ires)) ires = ret
    end subroutine

    integer(c_int) function get_vector_storage(this)
        class(opt), intent(in) :: this
        get_vector_storage = nlopt_get_vector_storage(this%o)
    end function
    subroutine set_vector_storage(this,dim,ires)
        class(opt), intent(inout) :: this
        integer(c_int), intent(in) :: dim
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_vector_storage(this%o,dim)
        if (present(ires)) ires = ret
    end subroutine

    subroutine set_default_initial_step(this,x,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: x(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_default_initial_step(this%o,x)
        if (present(ires)) ires = ret
    end subroutine

    subroutine set_initial_step_array(this,dx,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: dx(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_initial_step(this%o,dx)
        if (present(ires)) ires = ret
    end subroutine
    subroutine set_initial_step_scalar(this,dx,ires)
        class(opt), intent(inout) :: this
        real(c_double), intent(in) :: dx
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_set_initial_step1(this%o,dx)
        if (present(ires)) ires = ret
    end subroutine
    subroutine get_initial_step(this,x,dx,ires)
        class(opt), intent(in) :: this    
        real(c_double), intent(in) :: x(get_dimension(this))
        real(c_double), intent(out) :: dx(get_dimension(this))
        integer(c_int), intent(out), optional :: ires
        integer(c_int) :: ret
        ret = nlopt_get_initial_step(this%o,x,dx)
        if (present(ires)) ires = ret
    end subroutine


    integer(c_int) function version_major() result(major)
        integer(c_int) :: minor, bugfix
        call version(major,minor,bugfix)
    end function
    integer(c_int) function version_minor() result(minor)
        integer(c_int) :: major, bugfix
        call version(major,minor,bugfix)
    end function
    integer(c_int) function version_bugfix() result(bugfix)
        integer(c_int) :: major, minor
        call version(major,minor,bugfix)
    end function

    function algorithm_name(a) result(name)
        integer(c_int), intent(in) :: a
        character(len=:,kind=c_char), allocatable :: name
        character(len=256,kind=c_char), pointer :: f_string
        call c_f_pointer(nlopt_algorithm_name(a),f_string)
        name = f_string(1:index(f_string,c_null_char))
    end function

end module nlopt






module my_test_problem

    use iso_c_binding
    implicit none
    private

    public :: myfunc, myconstraint

contains

    real(c_double) function myfunc(n,x,grad,data)
        integer(c_int), intent(in), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(out), optional :: grad(n)
        type(c_ptr), value :: data

        if (present(grad)) then
            grad(1) = 0.0_c_double
            grad(2) = 0.5_c_double/sqrt(x(2))
        end if
        myfunc = sqrt(x(2))
    end function

    real(c_double) function myconstraint(n,x,gradient,func_data) bind(c)
        integer(c_int), intent(in), value :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(out), optional :: gradient(n)
        type(c_ptr), value :: func_data

        real(c_double), pointer :: d(:)
        real(c_double) :: a, b

        call c_f_pointer(func_data,d,[2])

        a = d(1)
        b = d(2)

        if (present(gradient)) then
            gradient(1) = 3._c_double*a*(a*x(1) + b)**2
            gradient(2) = 0.0_c_double
        end if
        myconstraint = (a*x(1) + b)**3 - x(2)
    end function

end module

module functor_mod

    use iso_c_binding, only: c_int, c_double
    use nlopt_user_func_mod, only: nlopt_user_func

    implicit none
    private

    public :: square

    type, extends(nlopt_user_func) :: square
    contains
        procedure, public :: eval => eval_square
    end type

contains

    real(c_double) function eval_square(this,n,x,grad)
        class(square), intent(in) :: this
        integer(c_int), intent(in) :: n
        real(c_double), intent(in) :: x(n)
        real(c_double), intent(out), optional :: grad(n)

        if (present(grad)) then
            grad(1) = 0.0_c_double
            grad(2) = 0.5_c_double/sqrt(x(2))
        end if
        eval_square = sqrt(x(2))
    end function

end module functor_mod

program main

    use iso_c_binding, only: c_int, c_double, c_ptr
    use my_test_problem, only: myfunc, myconstraint

    use nlopt, only: algorithm_name, version, opt, new_opt

    use nlopt_c_interface
    
    use nlopt_enum, only : NLOPT_LD_MMA

    use functor_mod, only: square

    implicit none


    call procedural_example
    call oo_example

contains

    subroutine procedural_example()

        integer(c_int) :: major, minor, bugfix
        integer(c_int), parameter :: n = 2

        type(c_ptr) :: opt, cd1,cd2

        real(c_double), dimension(n) :: x, lb
        real(c_double), target :: d1(2), d2(2)
        integer(c_int) :: ires
        real(c_double) :: optf

        type(c_funptr) :: c_func, c_constraint

        print *, "========= PROCEDURAL EXAMPLE =========="

        call version(major,minor,bugfix)
        print *, "NLopt version ",major,minor,bugfix

        opt = nlopt_create(NLOPT_LD_MMA,n)
        print *, "Algorithm = ", algorithm_name(nlopt_get_algorithm(opt))
        print *, "Dimension = ", nlopt_get_dimension(opt)

        lb = [-huge(1.0_c_double),0.0_c_double]
        ires = nlopt_set_lower_bounds(opt,lb)
        print *, "Lower bounds are = ", lb, " with return status ", ires

        ! Fortran function to C function pointer
        c_func = c_funloc(myfunc)
        ires = nlopt_set_min_objective(opt,c_func,c_null_ptr)


        ! Fortran constraint to C function pointer
        c_constraint = c_funloc(myconstraint)

        d1 = [2.0_c_double,0.0_c_double]
        cd1 = c_loc(d1)
        ires = nlopt_add_inequality_constraint(opt,c_constraint,cd1,1.d-8)
        
        d2 = [-1._c_double, 1.0_c_double]
        cd2 = c_loc(d2)
        ires = nlopt_add_inequality_constraint(opt,c_constraint,cd2,1.d-8)

        ires = nlopt_set_xtol_rel(opt,1.d-4)


        x = [1.234_c_double,5.678_c_double]
        ires = nlopt_optimize(opt,x,optf)

        if (ires < 0) then
            print *, "Nlopt failed!"
        else
            print *, "Found minimum at ", x
            print *, "Minimum value = ", optf
        end if

        ! opt_copy = nlopt_copy(opt)
        call nlopt_destroy(opt)

        ! print *, opt, opt_copy
    end subroutine


    subroutine oo_example()

        integer(c_int) :: major, minor, bugfix
        integer(c_int), parameter :: n = 2

        type(opt) :: myopt, myopt2
        type(c_ptr) :: cd1, cd2

        real(c_double), dimension(n) :: x, lb
        real(c_double), target :: d1(2), d2(2)
        integer(c_int) :: ires
        real(c_double) :: optf

        type(square) :: square_func

        print *, "========= OO EXAMPLE =========="

        call version(major,minor,bugfix)
        print *, "NLopt version ",major,minor,bugfix

        myopt = opt(a=NLOPT_LD_MMA,n=n,object_name="myopt")
        ! myopt2 = opt(myopt)
        print *, "Algorithm = ", myopt%get_algorithm_name()
        print *, "Dimension = ", myopt%get_dimension()

        print*, "algorithm_name = "//algorithm_name(5)

        lb = [-huge(1.0_c_double),0.0_c_double]
        call myopt%set_lower_bounds(lb)
        ! Fortran function to C function pointer
        ! c_func = c_funloc(myfunc)
        ! call myopt%set_min_objective(myfunc,c_null_ptr)

        call myopt%set_min_objective(square_func)


        d1 = [2.0_c_double,0.0_c_double]
        call myopt%add_inequality_constraint(myconstraint,c_loc(d1),tol=-1.d-8,ires=ires)
        ! if (ires < 0) then
        !     write(*,*) "something went wrong: ", myopt%get_errmsg()
        !     stop 0
        ! end if
        ! print *, "errmsg: ", myopt%get_errmsg()

        d2 = [-1._c_double, 1.0_c_double]
        cd2 = c_loc(d2)
        call myopt%add_inequality_constraint(myconstraint,cd2,1.d-8)

        call myopt%set_xtol_rel(1.d-4)
        
        x = [1.234_c_double,5.678_c_double]
        ires = myopt%optimize(x,optf)

        if (myopt%last_optimize_result() < 0) then
            print *, "Nlopt failed!"
        else
            print *, "Found minimum at ", x
            print *, "Minimum value = ", optf
        end if

        ! automatic finalization
    end subroutine



end program
"""
    process_expr(expr; kwargs...)

High-level warpper for processing expression with sub-tree operators
"""
function process_expr(m::PODNonlinearModel)

    expr_initialization(m)      # S0 : initialize the space for parsing and analyzing
    expr_preprocess(m)          # S1 : pre-process the negative sign in expressions
    expr_parsing(m)             # S2 : parsing the expressions for nonlinear information
    expr_conversion(m)          # S3 : convert lifted(linear) expressions into affine function
    expr_finalized(m)           # S4 : finalize process by extracting some measurements

    return
end

"""
	STEP 1: initialize the expression/ space
"""
function expr_initialization(m::PODNonlinearModel)

	# 0 : deepcopy data into mip lifted expr place holders
	m.bounding_obj_expr_mip = deepcopy(m.obj_expr_orig)
	m.bounding_obj_mip = Dict()

	for i in 1:m.num_constr_orig
		push!(m.bounding_constr_expr_mip, deepcopy(m.constr_expr_orig[i]))
		push!(m.bounding_constr_mip, Dict())
	end

	return
end

"""
	STEP 2: preprocess expression for trivial sub-trees and nasty pieces for easier later process
"""
function expr_preprocess(m::PODNonlinearModel)

	expr_resolve_const(m.bounding_obj_expr_mip)
	expr_resolve_sign(m.bounding_obj_expr_mip)
	expr_flatten(m.bounding_obj_expr_mip)
	for i in 1:m.num_constr_orig
		expr_resolve_const(m.bounding_constr_expr_mip[i])
		expr_resolve_sign(m.bounding_constr_expr_mip[i])
		expr_flatten(m.bounding_constr_expr_mip[i].args[2])
	end

	return
end

"""
	STEP 3: parse expression for patterns on either the generic level or term level
"""
function expr_parsing(m::PODNonlinearModel)

	is_strucural = expr_constr_parsing(m.bounding_obj_expr_mip, m)
	if !is_strucural
		m.bounding_obj_expr_mip = expr_term_parsing(m.bounding_obj_expr_mip, 0, m)
		m.obj_structure = :generic_linear
	end
	(m.loglevel > 99) && println("[OBJ] $(m.obj_expr_orig)")

	for i in 1:m.num_constr_orig
		is_strucural = expr_constr_parsing(m.bounding_constr_expr_mip[i], m, i)
		if !is_strucural
			m.bounding_constr_expr_mip[i] = expr_term_parsing(m.bounding_constr_expr_mip[i], i, m)
			m.constr_structure[i] = :generic_linear
		end
		(m.loglevel > 99) && println("[CONSTR] $(m.constr_expr_orig[i])")
	end

	return
end

"""
	STEP 4: convert the parsed expressions into affine-based function that can be used for adding JuMP constraints
"""
function expr_conversion(m::PODNonlinearModel)

	if m.obj_structure == :generic_linear
		m.bounding_obj_mip = expr_linear_to_affine(m.bounding_obj_expr_mip)
		m.obj_structure = :affine
	end
	m.loglevel > 99 && println("type :: ", m.obj_structure)
	m.loglevel > 99 && println("lifted ::", m.bounding_obj_expr_mip)
	m.loglevel > 99 && println("coeffs ::", m.bounding_obj_mip[:coefs])
	m.loglevel > 99 && println("vars ::", m.bounding_obj_mip[:vars])
	m.loglevel > 99 && println("sense ::", m.bounding_obj_mip[:sense])
	m.loglevel > 99 && println("rhs ::", m.bounding_obj_mip[:rhs])
	m.loglevel > 99 && println("----------------")


	for i in 1:m.num_constr_orig
		if m.constr_structure[i] == :generic_linear
			m.bounding_constr_mip[i] = expr_linear_to_affine(m.bounding_constr_expr_mip[i])
			m.constr_structure[i] = :affine
		end
		m.loglevel > 99 && println("type :: ", m.constr_structure[i])
		m.loglevel > 99 && println("lifted ::", m.bounding_constr_expr_mip[i])
		m.loglevel > 99 && println("coeffs ::", m.bounding_constr_mip[i][:coefs])
		m.loglevel > 99 && println("vars ::", m.bounding_constr_mip[i][:vars])
		m.loglevel > 99 && println("sense ::", m.bounding_constr_mip[i][:sense])
		m.loglevel > 99 && println("rhs ::", m.bounding_constr_mip[i][:rhs])
		m.loglevel > 99 && println("----------------")
	end

	return
end


"""
	STEP 5: collect measurements and information as needed for handly operations in the algorithm section
"""
function expr_finalized(m::PODNonlinearModel)

	# TODO: update
	for i in keys(m.nonlinear_terms)
        if m.nonlinear_terms[i][:nonlinear_type] in POD_C_MONOMIAL
    		for var in i
    			@assert isa(var.args[2], Int)
    			if !(var.args[2] in m.all_nonlinear_vars)
    				push!(m.all_nonlinear_vars, var.args[2])
    			end
    		end
        elseif m.nonlinear_terms[i][:nonlinear_type] in POD_C_TRIGONOMETRIC
            for var in m.nonlinear_terms[i][:var_idxs]
                @assert isa(var, Int)
                if !(var in m.all_nonlinear_vars)
                    push!(m.all_nonlinear_vars, var)
                end
            end
        end
	end

	m.all_nonlinear_vars = sort(m.all_nonlinear_vars)
    m.num_var_linear_mip = length(m.linear_terms)
	m.num_var_nonlinear_mip = length(m.nonlinear_terms)
	m.num_constr_convex = length([i for i in m.constr_structure if i == :convex])

	return m
end

"""
    expr_term_parsing(expr, m::PODNonlinearModel, level=0)

Recognize and process nonlinear terms in an expression
"""
function expr_term_parsing(expr, constr_id::Int, m::PODNonlinearModel, level=0; options...)

    cnt = 0
    for node in expr.args
        cnt += 1
        if isa(node, Float64) || isa(node, Int) || isa(node, Symbol)
            continue
        elseif node.head == :call
            expr.args[cnt] = expr_term_parsing(node, constr_id, m, level+1)
        elseif node.head == :ref
            continue
        else
            error("Type issue during expression parsing. ")
        end
    end

    return expr_resolve_term_pattern(expr, constr_id, m)
end

"""
    expr_resolve_term_pattern(expr, m::PODNonlinearModel)

This function recognizes, stores, and replaces a sub-tree `expr` with available
user-defined/built-in structures patterns. The procedure is creates the required number
of lifted variables based on the patterns that it it trying to recognize.
Then, go through all built-in structures and perform operatins to convexify the problem.

Specific structure pattern information will be described formally.
"""
function expr_resolve_term_pattern(expr, constr_id::Int, m::PODNonlinearModel; kwargs...)

    # First process user-defined structures in-cases of over-ride
    for i in 1:length(m.term_patterns)
        skip, expr = eval(m.term_patterns[i])(expr, constr_id, m)
        skip && return expr
    end

    # LEVEL 1 : : Recognize all built-in structural patterns
    skip, expr = resolve_binprod_term(expr, constr_id, m)           #L1 : binprod = binary products
    skip && return expr

    skip, expr = resolve_bpml_term(expr, constr_id, m)              #L1 : bpml = binary product & multilinear
    skip && return expr

    # LEVEL 2 : : Recognize all built-in structural patterns
    skip, expr = resolve_bilinear_term(expr, constr_id, m)          #L2
    skip && return expr

    skip, expr = resolve_monomial_term(expr, constr_id, m)          #L2 : must go before multilinear
    skip && return expr

    skip, expr = resolve_multilinear_term(expr, constr_id, m)       #L2
    skip && return expr

    skip, expr = resolve_sincos_term(expr, constr_id, m)            #L2
    skip && return expr

    return expr # if no structure is detected, simply return the original tree
end


"""
    TODO: docstring
    General funtioan to store a term
"""
function store_nl_term(m::PODNonlinearModel, nl_key, var_idxs, term_type, operator::Symbol, evaluator)

    l_cnt = length(keys(m.linear_terms))
    nl_cnt = length(keys(m.nonlinear_terms))

    y_idx = m.num_var_orig + nl_cnt + l_cnt  + 1   # y is always lifted var
    lifted_var_ref = Expr(:ref, :x, y_idx)
    lifted_constr_ref = build_constr_block(y_idx, var_idxs, operator)

    m.nonlinear_terms[nl_key] = Dict(:lifted_var_ref => lifted_var_ref,
                                    :id => nl_cnt + 1,
                                    :y_idx => y_idx,
                                    :y_type => resolve_lifted_var_type([m.var_type[k] for k in var_idxs], operator),
                                    :var_idxs => var_idxs,
                                    :ref => nl_key,
                                    :evaluator => evaluator,
                                    :lifted_constr_ref => lifted_constr_ref,
                                    :constr_id => Set(),
                                    :nonlinear_type => term_type,
                                    :convexified => false)

    m.term_seq[nl_cnt+l_cnt+1] = nl_key                              # Assistive information

    push!(m.var_type, m.nonlinear_terms[nl_key][:y_type])    # Keep track of the lifted var type
    (m.loglevel) > 99 && println("found lifted $(term_type) term $(lifted_constr_ref)")
    return y_idx
end

function store_linear_term(m::PODNonlinearModel, term_key, expr)

    l_cnt = length(keys(m.linear_terms))
    nl_cnt = length(keys(m.nonlinear_terms))

    y_idx = m.num_var_orig + nl_cnt + l_cnt + 1

    lifted_var_ref = Expr(:ref, :x, y_idx)
    lifted_constr_ref = Expr(:call, :(==), lifted_var_ref, expr)

    m.linear_terms[term_key] = Dict(:lifted_var_ref => lifted_var_ref,
                                    :id => length(keys(m.linear_terms)) + 1,
                                    :ref => term_key,
                                    :y_idx => y_idx,
                                    :y_type => resolve_lifted_var_type([m.var_type[k[2]] for k in term_key[:coef_var]], :+),
                                    :evaluator => linear,
                                    :lifted_constr_ref => lifted_constr_ref,
                                    :constr_id => Set())

    m.term_seq[l_cnt+nl_cnt + 1] = term_key
    push!(m.var_type, m.linear_terms[term_key][:y_type]) # Keep track of the lifted var type
    m.loglevel > 99 && println("found lifted linear term $expr = $(lifted_var_ref)")

    return y_idx
end

function lift_nl_term(m::PODNonlinearModel, nl_key, constr_id::Int, scalar = 1.0)
    push!(m.nonlinear_terms[nl_key][:constr_id], constr_id)

    if scalar == 1.0
        return m.nonlinear_terms[nl_key][:lifted_var_ref]
    else
        return Expr(:call, :*, m.nonlinear_terms[nl_key][:lifted_var_ref], scalar)
    end
end

function lift_linear_term(m::PODNonlinearModel, term_key, constr_id::Int)

    push!(m.linear_terms[term_key][:constr_id], constr_id)
    return m.linear_terms[term_key][:lifted_var_ref]

    return
end

function resolve_linear_term(expr, constr_id::Int, m::PODNonlinearModel)

    @assert expr.head == :call
    coef_fetch = Dict(:+ => 1.0, :- => -1.0)

    # Re-process the expression sub-tree [REQUIRED]
    expr_resolve_const(expr)
    expr_resolve_sign(expr)
    expr_flatten(expr)

    if expr.args[1] in [:+, :-]
        scalar = 0.0
        coef_var = Set()
        for i in 2:length(expr.args)  # TODO: Consider recursive operation
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                (i == 2) ? scalar=expr.args[i] : scalar+=coef_fetch[expr.args[1]]*expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue #should never happen
            if (expr.args[i].head==:ref) && isa(expr.args[i].args[2], Int)
                (i == 2) ? push!(coef_var, (1.0, expr.args[i].args[2])) : push!(coef_var, (coef_fetch[expr.args[1]],expr.args[i].args[2]))
                continue
            end
            if expr.args[i].head == :call && expr.args[i].args[1] == :* && length(expr.args[i].args) == 3
                sub_coef = [j for j in expr.args[i].args if (isa(j, Int) || isa(j, Float64))]
                sub_vars = [j.args[2] for j in expr.args[i].args if ((:head in fieldnames(j)) && j.head == :ref)]
                (isempty(sub_coef) || isempty(sub_vars)) && return false, expr
                (length(sub_coef) != 1 || length(sub_vars) != 1) && return false, expr
                (i == 2) ? push!(coef_var, (1.0*sub_coef[1], sub_vars[1])) : push!(coef_var, (coef_fetch[expr.args[1]]*sub_coef[1], sub_vars[1]))
                continue
            end
            if expr.args[i].head == :call && expr.args[i].args[1] in [:-,:+] && length(expr.args[i].args) == 2
                expr.args[i].args[1] == :+ ? sub_coef = [1.0] : sub_coef = [-1.0]
                sub_vars = [j.args[2] for j in expr.args[i].args if ((:head in fieldnames(j)) && j.head == :ref)]
                isempty(sub_vars) && return false, expr
                length(sub_vars) != 1 && return false, expr
                (i == 2) ? push!(coef_var, (1.0*sub_coef[1], sub_vars[1])) : push!(coef_var, (coef_fetch[expr.args[1]]*sub_coef[1], sub_vars[1]))
            else
                return false, expr
            end
        end
        # By reaching here, it is already certain that we have found the term, always treat with :+
        term_key = Dict(:scalar=>scalar, :coef_var=>coef_var, :sign=>:+)
        if term_key in keys(m.linear_terms)
            return true, lift_linear_term(m, term_key, constr_id)
        else
            store_linear_term(m, term_key, expr)
            return true, lift_linear_term(m, term_key, constr_id)
        end
    elseif expr.args[1] in [:*] && length(expr.args) == 3
        # For terms like (3*x)*y
        scalar = 0.0
        coef_var = Set()

        sub_coef = [i for i in expr.args if (isa(i, Int) || isa(i, Float64))]
        sub_vars = [i.args[2] for i in expr.args if ((:head in fieldnames(i)) && i.head == :ref)]
        (isempty(sub_coef) || isempty(sub_vars)) && return false, expr
        (length(sub_coef) != 1 || length(sub_vars) != 1) && return false, expr
        push!(coef_var, (1.0*sub_coef[1], sub_vars[1]))

        # By reaching here, it is already certain that we have found the term, always treat with :+
        term_key = Dict(:scalar=>scalar, :coef_var=>coef_var, :sign=>:+)
        if term_key in keys(m.linear_terms)
            return true, lift_linear_term(m, term_key, constr_id)
        else
            store_linear_term(m, term_key, expr)
            return true, lift_linear_term(m, term_key, constr_id)
        end
    end

    return false, expr
end


bpml(k,vec) = prod([vec[i] for i in k[:var_idxs]])
discmulti(k, vec) = prod([vec[i] for i in k[:var_idxs]])
binint(l, vec) = prod([vec[i] for i in k[:var_idxs]])
intprod(k, vec) = prod([vec[i] for i in k[:var_idxs]])
binprod(k, vec) = prod([vec[i] for i in k[:var_idxs]])
binlin(k,vec) = prod([vec[i] for i in k[:var_idxs]])
intlin(k,vec) = prod([vec[i] for i in k[:var_idxs]])
bilinear(k,vec) = prod([vec[i] for i in k[:var_idxs]])
multilinear(k,vec) = prod([vec[i] for i in k[:var_idxs]])
monomial(k, vec) = vec[k[:var_idxs][1]]^2
sincos(k, vec) = eval(k[:nonlinear_type])(vec[k[:var_idxs][1]])
linear(k, vec) = sum([i[1]*vec[i[2]] for i in k[:ref][:coef_var]])



function resolve_discmulti_term(expr, constr_id::Int, m::PODNonlinearModel)

    # Alwasy construct the binlin term after lifting
    @assert expr.head == :call

    if (expr.args[1] == :*)
        # Pattern: coefficients * x * y * z ..., where x, y, z are all binary variables
        var_idxs = []
        var_types = []
        scalar = 1.0
        for i in 1:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_types, m.var_type[expr.args[i].args[2]])
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                push!(var_types, m.var_type[linear_lift_var.args[2]])
                continue
            end
        end

        term_key = [Expr(:ref, :x, idx) for idx in var_idxs]

        cont_var_idxs = [idx for idx in var_idxs if m.var_type[idx] == :Cont]
        bin_var_idxs = [idx for idx in var_idxs if m.var_type[idx] == :Bin]
        int_var_idxs = [idx for idx in var_idxs if m.var_type[idx] == :Int]

        # Must carry at both discrete and continous variables
        isempty(int_var_idxs) && isempty(bin_var_idxs) && return false, expr
        isempty(cont_var_idxs) && return false, expr

        # Lift clusters of continous variables multiplication if necessary
        if length(cont_var_idxs) > 1
            ml_term_key = [Expr(:ref, :x, idx) for idx in cont_var_idxs]
            ml_term_expr = Expr(:call, :*)
            for idx in cont_var_idxs
                push!(ml_term_expr.args, Expr(:ref, :x, idx))
            end
            ml_lift_term = expr_resolve_term_pattern(ml_term_expr, constr_id, m)
            ml_idx = ml_lift_term.args[2]
        else
            ml_idx = cont_var_idxs[1]
        end

        # Lift clusters of binary vars multiplication if necessary
        if length(bin_var_idxs) > 1
            bp_term_key = [Expr(:ref, :x, idx) for idx in bin_var_idxs]
            bp_term_expr = Expr(:call, :*)
            for idx in bin_var_idxs
                push!(bp_term_expr.args, Expr(:ref, :x, idx))
            end
            bp_lift_term = expr_resolve_term_pattern(bp_term_expr, constr_id, m)
            bp_idx = bp_lift_term.args[2]
        else
            isempty(bin_var_idxs) ? bp_idx = -1 : bp_idx = bin_var_idxs[1]
        end

        # lift clusters of integer varis multiplication if necessary
        if length(int_var_idxs) > 1
            ip_term_key = [Expr(:ref, :x, idx) for idx in int_var_idxs]
            ip_term_expr = Expr(:call, :*)
            for idx in cont_var_idxs
                push!(ip_term_expr.args, Expr(:ref, :x, idx))
            end
            ip_lift_term = expr_resolve_term_pattern(ip_term_expr, constr_id, m)
        else
            isempty(int_var_idxs) ? ip_idx = -1 : ip_idx = ip_var_idxs[1]
        end

        if bp_idx < 0 # intlin term if no binary variable
            intlin_key = [Expr(:ref, :x, ip_idx), Expr(:ref, :x, ml_idx)]
            intlin_idxs = [ip_idx, ml_idx;]
            intlin_key in keys(m.nonlinear_terms) || store_nl_term(m, intlin_key, intlin_idxs, :INTLIN, :*, intlin)
            return true, lift_nl_term(m, intlin_key, constr_id, scalar)
        end

        if ip_idx < 0 # binlin term if no integer variable
            binlin_key = [Expr(:ref, :x, bp_idx), Expr(:ref, :x, ml_idx)]
            binlin_idxs = [bp_idx, ml_idx;]
            binlin_key in keys(m.nonlinear_terms) || store_nl_term(m, binlin_key, intlin_idxs, :BINLIN, :*, binlin)
            return true, lift_nl_term(m, binlin_key, constr_id, scalar)
        end

        # Otherwise, first :intlin term then :binlin term by assumption
        intlin_key = [Expr(:ref, :x, ip_idx), Expr(:ref, :x, ml_idx)]
        intlin_expr = Expr(:call, :*)
        push!(intlin_expr.args, Expr(:ref, :x, ip_idx))
        push!(intlin_expr.args, Expr(:ref, :x, ml_idx))
        intlin_lift = expr_resolve_term_pattern(intlin_expr, constr_id, m)
        intlin_idx = intlin_lift.args[2]

        binlin_key = [Expr(:ref, :x, bp_idx), Expr(:ref, :x, intlin_idx)]
        binlin_idxs = [bp_idx, intlin_idx;]
        binlin_key in keys(m.nonlinear_terms) || store_nl_term(m, binlin_key, intlin_idxs, :BINLIN, :*, binlin)
        return true, lift_nl_term(m, binlin_key, constr_id, scalar)

    end

    return false, expr
end

function resolve_intprod_term(expr, constr_id::Int, m::PODNonlinearModel)
end

function resolve_intlin_term(expr, constr_id::Int, m::PODNonlinearModel)
end

"""
    Recognize prodcuts of binary variables and multilinear products

        General Case : x1 * x2 .. * xN * y1 * y2 .. * yM
            where x are binary variables, y are continous variables

        Special Case : x * y
            where x is binary and y is continuous

    Re-Directs to resolve_binlin_term() & resolve_binprod_term()
"""
function resolve_bpml_term(expr, constr_id::Int, m::PODNonlinearModel)

    # Alwasy construct the binlin term after lifting
    @assert expr.head == :call

    if (expr.args[1] == :*)

        var_idxs = []
        var_types = []
        scalar = 1.0

        for i in 1:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_types, m.var_type[expr.args[i].args[2]])
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                push!(var_types, m.var_type[linear_lift_var.args[2]])
                continue
            end
        end

        cont_var_idxs = [idx for idx in var_idxs if m.var_type[idx] == :Cont]
        bin_var_idxs = [idx for idx in var_idxs if m.var_type[idx] == :Bin]

        # Must carry at both discrete and continous variables
        isempty(bin_var_idxs) && return false, expr
        isempty(cont_var_idxs) && return false, expr

        # Lift clusters of continous vars multiplication if necessary
        if length(cont_var_idxs) > 1
            ml_term_key = [Expr(:ref, :x, idx) for idx in cont_var_idxs]
            ml_term_expr = Expr(:call, :*)
            for idx in cont_var_idxs
                push!(ml_term_expr.args, Expr(:ref, :x, idx))
            end
            ml_lift_term = expr_resolve_term_pattern(ml_term_expr, constr_id, m)
            ml_idx = ml_lift_term.args[2]
        else
            ml_idx = cont_var_idxs[1]
        end

        # Lift clusters of binary vars multiplication if necessary
        if length(bin_var_idxs) > 1
            bp_term_key = [Expr(:ref, :x, idx) for idx in bin_var_idxs]
            bp_term_expr = Expr(:call, :*)
            for idx in bin_var_idxs
                push!(bp_term_expr.args, Expr(:ref, :x, idx))
            end
            bp_lift_term = expr_resolve_term_pattern(bp_term_expr, constr_id, m)
            bp_idx = bp_lift_term.args[2]
        else
            bp_idx = bin_var_idxs[1]
        end

        binlin_key = [Expr(:ref, :x, bp_idx), Expr(:ref, :x, ml_idx)]
        binlin_idxs = [bp_idx, ml_idx;]
        binlin_key in keys(m.nonlinear_terms) || store_nl_term(m, binlin_key, binlin_idxs, :BINLIN, :*, binlin)
        return true, lift_nl_term(m, binlin_key, constr_id, scalar)
    end

    return false, expr
end

"""
    Recognize products of binary variables : x1 * x2 * .. * xN
"""
function resolve_binprod_term(expr, constr_id::Int, m::PODNonlinearModel)
    @assert expr.head == :call
    if (expr.args[1] == :*)
        # Pattern: coefficients * x * y * z ..., where x, y, z are all binary variables
        var_idxs = []
        scalar = 1.0
        for i in 1:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] != :Bin && return false, expr
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                m.var_type[linear_lift_var.args[2]] != :Bin && false, expr
                push!(var_idxs, linear_lift_var.args[2])
                continue
            end
        end
        if length(var_idxs) >= 2
            term_key = [Expr(:ref, :x, idx) for idx in var_idxs]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :BINPROD, :*, binprod)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    elseif (expr.args[1] == :^) && length(expr.args) == 3
        # Pattern: (x)^(>2), where x is binary variable
        var_idxs = []
        power_scalar = 0
        scalar = 1.0
        for i in 2:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                power_scalar += expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] != :Bin && return false, expr
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                m.var_type[linear_lift_var.args[2]] != :Bin && false, expr
                push!(var_idxs, linear_lift_var.args[2])
                continue
            end
        end
        if length(var_idxs) == 1 && power_scalar > 2.0
            term_key = [Expr(:ref, :x, var_idxs[1]) for i in 1:power_scalar]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :BINPROD, :*, binprod)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    end

    return false, expr
end

"""
    Recognize bilinear terms: x * y, where x and y are continous variables
"""
function resolve_bilinear_term(expr, constr_id::Int, m::PODNonlinearModel)

    @assert expr.head == :call
    if (expr.args[1] == :*)  # confirm head (:*)
        # ----- Pattern : coefficient * x * y  ------ #
        # Collect children information for checking
        scalar = 1.0
        var_idxs = []
        for i in 2:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr    # Don't consider the discrete variable
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr  # Don't consider the discrete variable
                continue
            end
        end
        # Cofirm detection of patter A and perform store & lifting procedures
        if (length(var_idxs) == 2) && length(Set(var_idxs)) == 2
            term_key = [Expr(:ref, :x, var_idxs[1]), Expr(:ref, :x, var_idxs[2])]
            if term_key in keys(m.nonlinear_terms) || reverse(term_key) in keys(m.nonlinear_terms)
                term_key in keys(m.nonlinear_terms) ? term_key = term_key : term_key = reverse(term_key)
                return true, lift_nl_term(m, term_key, constr_id, scalar)
            else
                store_nl_term(m, term_key, var_idxs, :BILINEAR, :*, bilinear)
                return true, lift_nl_term(m, term_key, constr_id, scalar)
            end
        end
    end

    return false, expr
end

"""
    Recognize multilinear terms: x1 * x2 * .. * xN, where all x are continous variables
"""
function resolve_multilinear_term(expr, constr_id::Int, m::PODNonlinearModel)

    @assert expr.head == :call
    if (expr.args[1] == :*) # Pattern: coefficients * x * y * z ...
        var_idxs = []
        scalar = 1.0
        for i in 1:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr
                continue
            end
        end
        if length(var_idxs) > 2
            term_key = [Expr(:ref, :x, idx) for idx in var_idxs]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :MULTILINEAR, :*, multilinear)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    elseif (expr.args[1] == :^) && length(expr.args) == 3 # Pattern: (x)^(>2)
        var_idxs = []
        power_scalar = 0
        scalar = 1.0
        for i in 2:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                power_scalar += expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr # Avoid fetching terms with discrete variables
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr
                continue
            end
        end
        if length(var_idxs) == 1 && power_scalar > 2.0
            term_key = [Expr(:ref, :x, var_idxs[1]) for i in 1:power_scalar]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :MULTILINEAR, :*, multilinear)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    end

    return false, expr
end

"""
    Recognize monomial terms: x^2 or x * x, where x is continuous
"""
function resolve_monomial_term(expr, constr_id::Int, m::PODNonlinearModel)

    if (expr.args[1] == :^) && length(expr.args) == 3
        # Pattern: (x)^(2)
        var_idxs = []
        power_scalar = 0
        scalar = 1.0
        for i in 2:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                power_scalar += expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr # Avoid fetching terms with discrete variables
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr # Avoid fetching terms with discrete variables
                continue
            end
        end
        if length(var_idxs) == 1 && power_scalar == 2.0
            term_key = [Expr(:ref, :x, var_idxs[1]) for i in 1:2]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :MONOMIAL, :*, monomial)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    end

    # Type 2 monomial term : x * x
    if (expr.args[1] == :*)  # confirm head (:*)
        # ----- Pattern : coefficient * x * y  ------ #
        # Collect children information for checking
        scalar = 1.0
        var_idxs = []
        for i in 2:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            (isa(expr.args[i], Symbol)) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            !isempty(var_idxs) && m.var_type[var_idxs[end]] in [:Bin, :Int] && return false ,expr # Avoid fetching terms with discrete variables
            (expr.args[i].head == :call) && return false, expr
        end
        # Cofirm detection of patter A and perform store & lifting procedures
        if (length(var_idxs) == 2) && (length(Set(var_idxs)) == 1)
            term_key = [Expr(:ref, :x, var_idxs[1]), Expr(:ref, :x, var_idxs[2])]
            term_key = [Expr(:ref, :x, var_idxs[1]) for i in 1:2]
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, :MONOMIAL, :*, monomial)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    end

    return false, expr
end

"""
    Recognize sin/cos terms: sin(x) / cos(x)
"""
function resolve_sincos_term(expr, constr_id::Int, m::PODNonlinearModel)

    @assert expr.head == :call
    if expr.args[1] in [:sin, :cos]
        # Pattern: sin(a*x) or cos(a*x)
        operator = expr.args[1]
        scalar = 1.0
        var_idxs = []
        for i in 1:length(expr.args)
            if isa(expr.args[i], Float64) || isa(expr.args[i], Int)
                scalar *= expr.args[i]
                continue
            end
            isa(expr.args[i], Symbol) && continue
            (expr.args[i].head == :ref) && isa(expr.args[i].args[2], Int) && push!(var_idxs, expr.args[i].args[2])
            if (expr.args[i].head == :call)
                down_check, linear_lift_var = resolve_linear_term(expr.args[i], constr_id, m)
                !down_check && return false, expr
                push!(var_idxs, linear_lift_var.args[2])
                continue
            end
        end
        if length(var_idxs) == 1
            term_key = Dict(:operator=>operator, :scalar=>scalar, :vars=>var_idxs)
            term_key in keys(m.nonlinear_terms) || store_nl_term(m, term_key, var_idxs, term_key[:operator], term_key[:operator], sincos)
            return true, lift_nl_term(m, term_key, constr_id, scalar)
        end
    end

    return false, expr
end

"""
    Recognize convex constraints
    A scatch for type-A convex constraint expression
"""
function resolve_convex_constr(expr, m::PODNonlinearModel=nothing, idx::Int=0, scalar_bin=[], idxs_bin=[], power_bin=[], rhs=0.0)

    if expr.args[1] in [:(<=), :(>=)] && idx > 0
        expr_orig = :constr
        sense = expr.args[1]
        rhs = expr.args[3]
        subs, rhs_strip = expr_strip_const(expr.args[2])      # Focus on the regularized subtree (stripped with constants)
        rhs += rhs_strip                                      # TODO: check if sign is flipped
    elseif expr.args[1] == :(==)
        return false
    elseif idx == 0
        expr_orig = :obj
        subs, rhs = expr_strip_const(expr)              # Focus on the regularized subtree (stripped with constants)
    end

    for sub in subs
        (isa(sub, Float64) || isa(sub, Int) || isa(sub, Symbol)) && return false
        !(sub.args[1] in [:+,:-,:*]) && return false
        (sub.head == :ref) && return false
        (sub.head == :call) && (length(sub.args) < 3) && return false
        if sub.args[1] in [:-, :+]
            for i in 2:length(sub.args)
                if isa(sub.args[i], Float64) || isa(sub.args[i], Int)
                    (sub.args[1] == [:-]) && ((i == 1) ? rhs += sub.args[i] : rhs -= sub.args[i])
                    (sub.args[1] == [:+]) && (rhs += sub.args[i])
                elseif (sub.args[i].head == :ref)
                    return false
                elseif (sub.args[i].head == :call)
                    scalar, idxs, powers = expr_is_axn(sub.args[i])
                    (scalar == nothing) && return false
                    if length(Set(idxs)) == 1
                        push!(idxs_bin, idxs[1])
                        push!(power_bin, sum(powers))
                    else
                        return false
                    end
                    (sub.args[1] == :-) && ((i == 2) ? push!(scalar_bin, scalar) : push!(scalar_bin, -scalar))
                    (sub.args[1] == :+) && (push!(scalar_bin, scalar))
                end
            end
        elseif sub.args[1] in [:*]
            scalar, idxs, powers = expr_is_axn(sub)
            (scalar == nothing) && return false
            if length(Set(idxs)) == 1
                push!(idxs_bin, idxs[1])
                push!(power_bin, sum(powers))
            else
                return false
            end
            push!(scalar_bin, scalar)
        else
            return false    # don't support other operators
        end

        # @show rhs, scalar_bin, idxs_bin
        scalar_sign = sign(scalar_bin[1])
        if length(scalar_bin) > 1
            for i in 2:length(scalar_bin)
                !(scalar_sign == sign(scalar_bin[i])) && return false
            end
        end

        !(length(Set(power_bin)) == 1) && return false
        (expr.args[1] == :(<=)) && !(scalar_sign >= 0.0 && rhs >= 0.0) && return false
        (expr.args[1] == :(>=)) && !(scalar_sign <= 0.0 && rhs <= 0.0) && return false
        (expr.args[1] == :(<=)) && (scalar_sign <= 0.0) && return false
        (expr.args[1] == :(>=)) && (scalar_sign >= 0.0) && return false
    end

    if expr_orig == :constr
        # For anything reaches this point, we've detected most common attributes of a convex expression
        # Now, we should use the differences to indicate different types of convex expression
        convex_type = :Unknown

        # [BUG FIX | FORK]
        power_check = [((i > 1.0) && mod(i, 2) == 0) for i in power_bin]    # Special case for linear constraints with @NLconstraint
        isempty(power_check) && return false

        # Convex constraint Type-A
        # sum_i (c_i*x_i^p) <= K (K > 0, p is an even positive integer and x_i \in R)   => Convex
        power_check = [((i > 1.0) && mod(i, 2) == 0) for i in power_bin]
        (convex_type == :Unknown) && prod(power_check) && (convex_type = :convexA)

        # Type-B: Convex constraint
        # sum_i (c_i*x_i^p) <= K (K > 0, p >= 1 and x_i >= 0)                           => Convex
        lb_check = [m.l_var_orig[i.args[2]] >= 0.0 for i in idxs_bin]
        power_check = [(i > 1.0) for i in power_bin]
        (convex_type == :Unknown) && prod(lb_check) && prod(power_check) && (convex_type = :convexB)

        # Convex constraint Type-C
        # sum_i (c_i*x_i^p) >= K (K > 0, 0 < p < 1 and x_i >= 0)                        => Convex
        power_check = [((i<1) && (i>0.0)) for i in power_bin]
        lb_check = [m.l_var_orig[i.args[2]] >= 0.0 for i in idxs_bin]
        (convex_type == :Unknown) && prod(power_check) && prod(power_check) && (convex_type = :convexC)

        # Convex constraint Type-D
        # sum_i (c_i*x_i^p) <= K (K > 0, p <= 0 and x_i > 0)                            => Convex
        power_check = [i <= 0.0 for i in power_bin]
        lb_check =  [m.l_var_orig[i.args[2]] >= 0.0 for i in idxs_bin]
        (convex_type == :Unknown) && prod(power_check) && prod(power_check) && (convex_type = :convexD)

        # If we really cannot figure out what is going on...
        (convex_type == :Unknown) && return false

        # Recording the nonlinear info
        m.nonlinear_constrs[idx] = Dict(:expr_idx => idx,
                                        :convex_type => convex_type,
                                        :nonlinear_type => :convex,
                                        :expr_orig => :constraints,
                                        :expr_ref => deepcopy(expr),
                                        :convexified => false)
        # Recording the un-changed expression
        m.bounding_constr_expr_mip[idx] = expr

        # Recording structural identifier
        m.constr_structure[idx] = :convex

        # Recording the function for adding constraints
        m.bounding_constr_mip[idx] = Dict(:sense => sense,
                                          :coefs => scalar_bin,
                                          :vars => idxs_bin,
                                          :rhs => rhs,
                                          :cnt => length(idxs_bin),
                                          :powers => power_bin)
        return true

    elseif expr_orig == :obj

        convex_type = :Unknown

        # Follows the same mapping to convex constraints

        # Type-A: Convex objective function
        # sum_i (c_i*x_i^p) (p is an even positive integer and x_i \in R)   => Convex
        power_check = [((i > 1.0) && mod(i, 2) == 0) for i in power_bin]
        (convex_type == :Unknown) && prod(power_check) && (convex_type = :convexA)

        # Type-B: Convex objective function
        # sum_i (c_i*x_i^p) (p >= 1 and x_i >= 0)                           => Convex
        lb_check = [m.l_var_orig[i.args[2]] >= 0.0 for i in idxs_bin]
        power_check = [i > 1.0 for i in power_bin]
        (convex_type == :Unknown) && prod(lb_check) && prod(power_check) && (convex_type = :convexB)

        # Type-D: Convex objective function
        # sum_i (c_i*x_i^p) (p <= 0 and x_i > 0) => Convex
        power_check = [i <= 0.0 for i in power_bin]
        lb_check =  [m.l_var_orig[i.args[2]] >= 0.0 for i in idxs_bin]
        (convex_type == :Unknown) && prod(power_check) && prod(power_check) && (convex_type = :convexD)

        convex_type == :Unknown && return false

        # Recording the nonlinear info
        m.nonlinear_constrs[idx] = Dict(:expr_orig => :objective,
                                        :expr_idx => idx,
                                        :convex_type => convex_type,
                                        :nonlinear_type => :convex,
                                        :expr_ref => deepcopy(expr),
                                        :convexified => false)

        # Recording the un-changed expression
        m.bounding_obj_expr_mip = expr

        # Recording structural identifier
        m.obj_structure = :convex

        # Record a function that can be used to add objective function
        m.bounding_obj_mip = Dict(:sense => nothing,
                                  :coefs => scalar_bin,
                                  :vars => idxs_bin,
                                  :rhs => -rhs,
                                  :cnt => length(idxs_bin),
                                  :powers => power_bin)


    end

    return true
end

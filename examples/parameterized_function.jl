#literate_begin file="src/examples/parameterized_function.md"
#=
# Learning Parameterized Expressions

_Note: Parametric expressions are currently considered experimental and may change in the future._

Parameterized expressions in SymbolicRegression.jl allow you to discover symbolic expressions that contain
optimizable parameters. This is particularly useful when you have data that follows different patterns
based on some categorical variable, or when you want to learn an expression with constants that should
be optimized during the search.

In this tutorial, we'll generate synthetic data with class-dependent parameters and use symbolic regression to discover the parameterized expressions.

## The Problem

Let's create a synthetic dataset where the underlying function changes based on a class label:

```math
y = 2\cos(x_2 + 0.1) + x_1^2 - 3.2 \ \ \ \ \text{[class 1]} \\
\text{OR} \\
y = 2\cos(x_2 + 1.5) + x_1^2 - 0.5 \ \ \ \ \text{[class 2]}
```

We will need to simultaneously learn the symbolic expression and per-class parameters!
=#
using SymbolicRegression
using Random: MersenneTwister
using Zygote  #src
using MLJBase: machine, fit!, predict, report
using Test

#=
Now, we generate synthetic data, with these 2 different classes.
=#

X = let rng = MersenneTwister(0), n = 30
    (; x1=randn(rng, n), x2=randn(rng, n), class=rand(rng, 1:2, n))
end

#=
Now, we generate target values using the true model that
has class-dependent parameters:
=#
y = let P1 = [0.1, 1.5], P2 = [3.2, 0.5]
    [2 * cos(x2 + P1[class]) + x1^2 - P2[class] for (x1, x2, class) in zip(X.x1, X.x2, X.class)]
end

#=
## Setting up the Search

We'll configure the symbolic regression search to
use template expressions with parameters that _vary by class_
=#

stop_at = Ref(1e-4)  #src

# Get number of categories from the data
n_categories = length(unique(X.class))

# Create a template expression specification with 2 parameters
expression_spec = @template_spec(
    expressions = (f,), parameters = (p1=n_categories, p2=n_categories),
) do x1, x2, class
    f(x1, x2, p1[class], p2[class])
end
test_kwargs = if get(ENV, "SYMBOLIC_REGRESSION_IS_TESTING", "false") == "true"  #src
    (;  #src
        expression_spec=ParametricExpressionSpec(; max_parameters=2),  #src
        autodiff_backend=:Zygote,  #src
    )  #src
else  #src
    NamedTuple()  #src
end  #src

model = SRRegressor(;
    niterations=100,
    binary_operators=[+, *, /, -],
    unary_operators=[cos, exp],
    populations=30,
    expression_spec=expression_spec,
    test_kwargs...,  #src
    early_stop_condition=(loss, _) -> loss < stop_at[],  #src
);

#=
Now, let's set up the machine and fit it:
=#

mach = machine(model, X, y)

#=
At this point, you would run:

```julia
fit!(mach)
```

You can extract the best expression and parameters with:

```julia
report(mach).equations[end]
```

=#
#literate_end

fit!(mach)
idx1 = lastindex(report(mach).equations)
ypred1 = predict(mach, (data=X, idx=idx1))
loss1 = sum(i -> abs2(ypred1[i] - y[i]), eachindex(y)) / length(y)

# Should keep all parameters
stop_at[] = loss1 * 0.999
mach.model.niterations *= 2
fit!(mach)
idx2 = lastindex(report(mach).equations)
ypred2 = predict(mach, (data=X, idx=idx2))
loss2 = sum(i -> abs2(ypred2[i] - y[i]), eachindex(y)) / length(y)

# Should get better:
@test loss1 >= loss2

module DatasetModule

using Random: AbstractRNG, default_rng
using DynamicQuantities: Quantity

using ..UtilsModule: subscriptify, get_base_type
using ..ProgramConstantsModule: DATA_TYPE, LOSS_TYPE
using ...InterfaceDynamicQuantitiesModule: get_si_units, get_sym_units

"""
    Dataset{T<:DATA_TYPE,L<:LOSS_TYPE}

Abstract type for all dataset types in SymbolicRegression.jl.
"""
abstract type Dataset{T<:DATA_TYPE,L<:LOSS_TYPE} end

"""
    BasicDataset{T<:DATA_TYPE,L<:LOSS_TYPE} <: Dataset{T,L}

# Fields

- `X::AbstractMatrix{T}`: The input features, with shape `(nfeatures, n)`.
- `y::AbstractVector{T}`: The desired output values, with shape `(n,)`.
- `index::Int`: The index of the output feature corresponding to this
    dataset, if any.
- `n::Int`: The number of samples.
- `nfeatures::Int`: The number of features.
- `weights::Union{AbstractVector,Nothing}`: If the dataset is weighted,
    these specify the per-sample weight (with shape `(n,)`).
- `extra::NamedTuple`: Extra information to pass to a custom evaluation
    function. Since this is an arbitrary named tuple, you could pass
    any sort of dataset you wish to here.
- `avg_y`: The average value of `y` (weighted, if `weights` are passed).
- `use_baseline`: Whether to use a baseline loss. This will be set to `false`
    if the baseline loss is calculated to be `Inf`.
- `baseline_loss`: The loss of a constant function which predicts the average
    value of `y`. This is loss-dependent and should be updated with
    `update_baseline_loss!`.
- `variable_names::Array{String,1}`: The names of the features,
    with shape `(nfeatures,)`.
- `display_variable_names::Array{String,1}`: A version of `variable_names`
    but for printing to the terminal (e.g., with unicode versions).
- `y_variable_name::String`: The name of the output variable.
- `X_units`: Unit information of `X`. When used, this is a vector
    of `DynamicQuantities.Quantity{<:Any,<:Dimensions}` with shape `(nfeatures,)`.
- `y_units`: Unit information of `y`. When used, this is a single
    `DynamicQuantities.Quantity{<:Any,<:Dimensions}`.
- `X_sym_units`: Unit information of `X`. When used, this is a vector
    of `DynamicQuantities.Quantity{<:Any,<:SymbolicDimensions}` with shape `(nfeatures,)`.
- `y_sym_units`: Unit information of `y`. When used, this is a single
    `DynamicQuantities.Quantity{<:Any,<:SymbolicDimensions}`.
"""
mutable struct BasicDataset{
    T<:DATA_TYPE,
    L<:LOSS_TYPE,
    AX<:AbstractMatrix{T},
    AY<:Union{AbstractVector,Nothing},
    AW<:Union{AbstractVector,Nothing},
	AB<:Union{AbstractVector{<:Integer},Nothing},
	AUB<:Union{AbstractVector{<:Integer},Nothing},
    NT<:NamedTuple,
    XU<:Union{AbstractVector{<:Quantity},Nothing},
    YU<:Union{Quantity,Nothing},
    XUS<:Union{AbstractVector{<:Quantity},Nothing},
    YUS<:Union{Quantity,Nothing},
} <: Dataset{T,L}
    const X::AX
    const y::AY
    const index::Int
    const n::Int
    const nfeatures::Int
    const weights::AW
	const batch_assignments::AB
	const unique_batch_assignments::AUB
    const extra::NT
    const avg_y::Union{T,Nothing}
    use_baseline::Bool
    baseline_loss::L
    const variable_names::Array{String,1}
    const display_variable_names::Array{String,1}
    const y_variable_name::String
    const X_units::XU
    const y_units::YU
    const X_sym_units::XUS
    const y_sym_units::YUS
end

"""
    SubDataset{T<:DATA_TYPE,L<:LOSS_TYPE,D<:BasicDataset{T,L},I<:AbstractVector{Int}} <: Dataset{T,L}

A dataset type that represents a batch of data from a BasicDataset. Calls to `.X`, `.y`,
`.weights`, etc. will return the batched versions of these.
"""
struct SubDataset{T<:DATA_TYPE,L<:LOSS_TYPE,D<:BasicDataset{T,L},I<:AbstractVector{Int}} <:
       Dataset{T,L}
    _dataset::D
    _indices::I
end
@inline get_full_dataset(d::SubDataset) = getfield(d, :_dataset)
@inline get_indices(d::SubDataset) = getfield(d, :_indices)
@inline function Base.getproperty(d::SubDataset, prop::Symbol)
    if prop == :X
        return view(get_full_dataset(d).X, :, get_indices(d))
    elseif prop == :y
        y = get_full_dataset(d).y
        return isnothing(y) ? y : view(y, get_indices(d))
    elseif prop == :weights
        weights = get_full_dataset(d).weights
        return isnothing(weights) ? weights : view(weights, get_indices(d))
    elseif prop == :n
        return length(get_indices(d))
    else
        # Forward all other properties
        return getproperty(get_full_dataset(d), prop)
    end
end
@inline Base.propertynames(d::SubDataset) = propertynames(get_full_dataset(d))

dataset_fraction(d::SubDataset) = d.n / get_full_dataset(d).n

"""
    Dataset(X::AbstractMatrix{T},
            y::Union{AbstractVector{T},Nothing}=nothing,
            loss_type::Type=Nothing;
            weights::Union{AbstractVector, Nothing}=nothing,
			batch_assignments:: ...
            variable_names::Union{Array{String, 1}, Nothing}=nothing,
            y_variable_name::Union{String,Nothing}=nothing,
            extra::NamedTuple=NamedTuple(),
            X_units::Union{AbstractVector, Nothing}=nothing,
            y_units=nothing,
    ) where {T<:DATA_TYPE}

Construct a dataset to pass between internal functions. Returns a BasicDataset.
"""
function Dataset(
    X::AbstractMatrix{T},
    y::Union{AbstractVector,Nothing}=nothing,
    loss_type::Type{L}=Nothing;
    index::Int=1,
    weights::Union{AbstractVector,Nothing}=nothing,
	batch_assignments::Union{AbstractVector{<:Integer},Nothing},
    variable_names::Union{Array{String,1},Nothing}=nothing,
    display_variable_names=variable_names,
    y_variable_name::Union{String,Nothing}=nothing,
    extra::NamedTuple=NamedTuple(),
    X_units::Union{AbstractVector,Nothing}=nothing,
    y_units=nothing,
    # Deprecated:
    kws...,
) where {T<:DATA_TYPE,L}
    Base.require_one_based_indexing(X)
    y !== nothing && Base.require_one_based_indexing(y)
    # Deprecation warning:
    if haskey(kws, :loss_type)
        Base.depwarn(
            "The `loss_type` keyword argument is deprecated. Pass as an argument instead.",
            :Dataset,
        )
        return Dataset(
            X,
            y,
            kws[:loss_type];
            index,
            weights,
			batch_assignments,
            variable_names,
            display_variable_names,
            y_variable_name,
            extra,
            X_units,
            y_units,
        )
    end
	
	
    n = size(X, 2)
    nfeatures = size(X, 1)
    variable_names = @something(variable_names, ["x$(i)" for i in 1:nfeatures])
    display_variable_names = @something(
        display_variable_names, ["x$(subscriptify(i))" for i in 1:nfeatures]
    )
    y_variable_name = @something(y_variable_name, ("y" ∉ variable_names) ? "y" : "target")
    avg_y = if y === nothing || !(eltype(y) isa Number)
        nothing
    else
        if weights !== nothing
            sum(y .* weights) / sum(weights)
        else
            sum(y) / n
        end
    end
    out_loss_type = if L === Nothing
        T <: Complex ? get_base_type(T) : T
    else
        L
    end

	# Validation for batch_assignments if provided
    if batch_assignments !== nothing && length(batch_assignments) != n
        error("Length of batch_assignments ($(length(batch_assignments))) must match dataset size ($n)")
    end

	unique_batch_assignments = nothing
	if batch_assignments !== nothing
		unique_batch_assignments = unique(batch_assignments)
	end

    use_baseline = true
    baseline = one(out_loss_type)
    y_si_units = get_si_units(T, y_units)
    y_sym_units = get_sym_units(T, y_units)

    # TODO: Refactor
    # This basically just ensures that if the `y` units are set,
    # then the `X` units are set as well.
    X_si_units = let (_X = get_si_units(T, X_units))
        if _X === nothing && y_si_units !== nothing
            get_si_units(T, [one(T) for _ in 1:nfeatures])
        else
            _X
        end
    end
    X_sym_units = let _X = get_sym_units(T, X_units)
        if _X === nothing && y_sym_units !== nothing
            get_sym_units(T, [one(T) for _ in 1:nfeatures])
        else
            _X
        end
    end

    error_on_mismatched_size(nfeatures, X_si_units)

    return BasicDataset{
        T,
        out_loss_type,
        typeof(X),
        typeof(y),
        typeof(weights),
		typeof(batch_assignments),
		typeof(unique_batch_assignments),
        typeof(extra),
        typeof(X_si_units),
        typeof(y_si_units),
        typeof(X_sym_units),
        typeof(y_sym_units),
    }(
        X,
        y,
        index,
        n,
        nfeatures,
        weights,
		batch_assignments,
		unique_batch_assignments,
        extra,
        avg_y,
        use_baseline,
        baseline,
        variable_names,
        display_variable_names,
        y_variable_name,
        X_si_units,
        y_si_units,
        X_sym_units,
        y_sym_units,
    )
end

is_weighted(dataset::Dataset) = dataset.weights !== nothing

# COV_EXCL_START
get_full_dataset(d::BasicDataset) = d
get_indices(::BasicDataset) = nothing
dataset_fraction(d::BasicDataset) = 1.0
# COV_EXCL_END

function error_on_mismatched_size(_, ::Nothing)
    return nothing
end
function error_on_mismatched_size(nfeatures, X_units::AbstractVector)
    if nfeatures != length(X_units)
        error(
            "Number of features ($(nfeatures)) does not match number of units ($(length(X_units)))",
        )
    end
    return nothing
end

function has_units(dataset::Dataset)
    return dataset.X_units !== nothing || dataset.y_units !== nothing
end

# Used for Enzyme
function Base.fill!(d::Dataset, val)
    _fill!(d.X, val)
    _fill!(d.y, val)
    _fill!(d.weights, val)
    _fill!(d.extra, val)
    return d
end
_fill!(x::AbstractArray, val) = fill!(x, val)
_fill!(x::NamedTuple, val) = foreach(v -> _fill!(v, val), values(x))
_fill!(::Nothing, val) = nothing
_fill!(x, val) = x

function max_features(dataset::Dataset, _)
    return dataset.nfeatures
end

"""
    batch([rng::AbstractRNG,] dataset::BasicDataset, batch_size::Int) -> SubDataset
    batch(dataset::BasicDataset, indices::AbstractVector{Int}) -> SubDataset

Create a batched dataset by randomly sampling from the original dataset.

# Arguments
- `rng::AbstractRNG`: Random number generator to use for sampling
- `dataset::BasicDataset`: The dataset to sample from
- `batch_size::Int`: The size of the batch to create
"""
function batch(dataset::BasicDataset{T,L}, indices::AbstractVector{Int}) where {T,L}
    return SubDataset{T,L,typeof(dataset),typeof(indices)}(dataset, indices)
end

function batch(rng::AbstractRNG, dataset::BasicDataset{T,L}, batch_size::Int) where {T,L}
    # If batch assignments are provided, use them
    if dataset.batch_assignments !== nothing

        # Randomly select a batch
        batch_id = rand(rng, dataset.unique_batch_assignments)
        indices = findall(x -> x == batch_id, dataset.batch_assignments)
        return SubDataset{T,L,typeof(dataset),typeof(indices)}(dataset, indices)
    else
        # Fall back to original random sampling behavior
        return batch(dataset, rand(rng, 1:(dataset.n), batch_size))
    end

end

function batch(dataset::BasicDataset, batch_size::Int)
    return batch(default_rng(), dataset, batch_size)
end


end

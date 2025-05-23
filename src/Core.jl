module CoreModule

function create_expression end

include("Utils.jl")
include("ProgramConstants.jl")
include("Dataset.jl")
include("MutationWeights.jl")
include("OptionsStruct.jl")
include("Operators.jl")
include("ExpressionSpec.jl")
include("Options.jl")
include("InterfaceDataTypes.jl")

using .ProgramConstantsModule: RecordType, DATA_TYPE, LOSS_TYPE
using .DatasetModule:
    Dataset,
    BasicDataset,
    SubDataset,
    is_weighted,
    has_units,
    max_features,
    batch,
    get_indices,
    get_full_dataset,
    dataset_fraction
using .MutationWeightsModule: AbstractMutationWeights, MutationWeights, sample_mutation
using .OptionsStructModule:
    AbstractOptions,
    Options,
    ComplexityMapping,
    specialized_options,
    operator_specialization
using .OperatorsModule:
    get_safe_op,
    plus,
    sub,
    mult,
    square,
    cube,
    pow,
    safe_pow,
    safe_log,
    safe_log2,
    safe_log10,
    safe_log1p,
    safe_sqrt,
    safe_asin,
    safe_acos,
    safe_acosh,
    safe_atanh,
    neg,
    greater,
    less,
    greater_equal,
    less_equal,
    cond,
    relu,
    logical_or,
    logical_and,
    gamma,
    erf,
    erfc,
    atanh_clip
using .ExpressionSpecModule:
    AbstractExpressionSpec,
    ExpressionSpec,
    get_expression_type,
    get_expression_options,
    get_node_type
using .InterfaceDataTypesModule: init_value, sample_value, mutate_value

end

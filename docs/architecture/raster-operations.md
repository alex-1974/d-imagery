# Raster operation model

## Status

E5.0 architecture definition.

This document defines the conceptual operation layer above the resident raster
semantics and execution machinery established by E1-E4.

E5.0 deliberately introduces no public raster operation API and no generic
operation framework in production code.

## Purpose

The raster core now has enough concrete execution experience to define an
operation model from actual requirements rather than hypothetical abstraction.

E4 produced two materially different operation families:

```text
reduction
    one read-only source
    scalar result
    numeric semantics matter
    execution layout selects compatible kernels

copy
    one read-only source
    one writable target
    source/target relation matters
    non-overlap must be proved before the optimized kernel
```

The operation layer must accommodate both without pretending that their
operation-specific semantics are interchangeable.

The purpose of E5 is therefore to establish stable boundaries between:

```text
semantic request
capability discovery
relation proof
execution selection
kernel execution
```

while keeping each operation free to define the semantics it actually needs.

## Existing lower layers

E5 builds on the existing raster layers rather than replacing them.

```text
semantic resident data
    RasterView!T
    RasterLease!T

writable execution target
    RasterTargetPlane!T

execution capability
    PlaneExecutionTraits
    Universal
    Canonical
    Contiguous
    linearContiguous1D

execution adapters
    short-lived Mir slices

reference kernels
    scalar reduction
    scalar pointwise copy

specialized kernels
    fixedLane4 reduction
    proven-non-overlap memcpy copy

operation-specific dispatch
    dispatchFloatToDoubleSum
    tryCopyNonOverlappingContiguous1D
```

Mir remains an internal execution substrate. It is not part of semantic raster
types or the future public operation vocabulary.

## Core model

A raster operation is conceptually evaluated in five stages.

```text
1. semantic request
       |
       v
2. validate operation inputs
       |
       v
3. derive execution capabilities
       |
       v
4. establish required relational facts
       |
       v
5. select and execute a compatible kernel
```

These are architectural responsibilities, not a requirement to introduce five
runtime objects or five function calls.

A simple operation may collapse several stages into one small dispatcher.

## 1. Semantic request

The semantic request states what operation is required and any choices that
change its observable meaning.

Examples:

```text
sum float samples into double
    numeric semantics = strict

sum float samples into double
    numeric semantics = fixedLane4

copy source samples into target
    sample values preserved exactly
```

Operation semantics must not be inferred from storage layout.

For example:

```text
Contiguous
```

does not mean:

```text
fixedLane4
fast math
non-overlapping
unique
safe to memcpy
```

Storage capability and semantic policy remain independent dimensions.

## 2. Input validation

Each operation validates the logical inputs required by its own contract.

Possible checks include:

```text
plane index
shape compatibility
sample-type compatibility
empty operation semantics
policy enum validity
target availability
```

There is intentionally no universal operation error enum.

Different operations expose different failure modes and should retain
operation-specific result types until substantial common semantics emerge.

## 3. Execution capability

Execution capability describes what the concrete storage representation permits.

The current per-plane capability model remains:

```text
Universal
Canonical
Contiguous
linearContiguous1D
```

Capabilities are facts derived from validated raster metadata.

They are not promises supplied by callers.

Capability discovery may influence kernel selection but must not alter the
semantic request.

For example, strict reduction can use several execution layouts while
preserving one numeric operation graph:

```text
strict + Universal
    scalar Universal 2D

strict + Canonical
    scalar Canonical 2D

strict + Contiguous 2D
    scalar Contiguous 2D

strict + flat Contiguous 1D
    scalar Contiguous 1D
```

By contrast, the current fixedLane4 operation graph has the stronger capability
requirement:

```text
fixedLane4
    requires flat Contiguous 1D
```

Lack of the required capability is therefore an execution failure, not
permission to change semantics.

## 4. Relational facts

Some operations require facts involving more than one operand.

These are not properties of either operand in isolation.

The existing copy operation provides the first production example:

```text
source range
    +
target range
    ->
pairwise non-overlap relation
```

`RasterTargetPlane` therefore does not carry a persistent `noalias`,
`nonOverlapping`, or uniqueness property.

The current copy operation derives and consumes the relation inside the same
operation:

```text
source + target
      |
      v
exact physical intervals
      |
      +-- overlap              -> fail before write
      |
      +-- unrepresentable      -> fail before write
      |
      `-- proven non-overlap   -> memcpy
```

This establishes a general rule for the operation layer:

> Relational facts belong to the concrete operation invocation unless their
> lifetime and operand identity can be represented safely and usefully.

No persistent proof-token abstraction is justified yet.

Future examples may include:

```text
two-source alias relationships
source/target overlap rules for transforms
halo availability
neighborhood extent
compatible coordinate domains
```

Each should be introduced only when a real operation requires it.

## 5. Kernel selection and execution

A kernel is an implementation of a specific semantic operation under explicit
execution preconditions.

A kernel must not silently strengthen or weaken the semantic request.

Examples:

```text
scalarSumUniversal2D
    semantic graph: strict scalar sum
    capability: Universal

fixedLane4SumFloatToDoubleContiguous1D
    semantic graph: fixedLane4
    capability: flat Contiguous 1D

memcpy after checked non-overlap
    semantic graph: exact same-type copy
    capability: flat Contiguous 1D source + contiguous target
    relation: proven non-overlap
```

Kernel selection is allowed to exploit:

```text
storage capability
operation policy
proved relational facts
sample type
measured implementation evidence
```

but those dimensions remain conceptually separate.

## Operation-specific dispatch remains valid

E5 does not require replacement of the existing dispatchers by one generic
dispatcher.

Current forms are intentionally operation-specific:

```text
dispatchFloatToDoubleSum(...)
tryCopyNonOverlappingContiguous1D(...)
```

This is desirable because their contracts differ substantially.

The reduction dispatcher reasons about:

```text
numeric semantics
source execution capability
scalar result
```

The copy dispatcher reasons about:

```text
source capability
target shape/capability
physical address representability
source/target overlap
write-before-failure guarantees
```

A common generic dispatcher would currently erase useful distinctions.

## Comparison of current operations

| Concern | Float -> double sum | Same-type checked copy |
| --- | --- | --- |
| Read sources | one | one |
| Writable targets | none | one |
| Result | scalar `double` | value-only status |
| Semantic policy | `strict`, `fixedLane4` | none |
| Storage capability | Universal through flat Contiguous | flat Contiguous source |
| Target capability | n/a | contiguous |
| Pairwise relation | none | proven non-overlap |
| Empty behavior | additive identity | successful no-op for matching shape |
| Specialized execution | fixedLane4 | `memcpy` |
| Silent fallback allowed | no | no |
| Public API | none yet | none yet |

The table is evidence that the operation layer has common phases but not yet
enough common *types* to justify a generic framework.

## Concepts that are shared

The following concepts are stable enough to use consistently across operations:

```text
semantic contract
operation-specific policy
validated operands
execution capability
relational fact
kernel precondition
kernel selection
operation-specific result
```

These are vocabulary and architectural boundaries.

They do not imply corresponding base classes, interfaces, enums, or structs.

## Concepts that are deliberately not generalized

E5.0 does not introduce:

```text
GenericRasterOperation
GenericOperationResult
GenericExecutionPolicy
GenericPlanner
GenericKernel
GenericAliasPolicy

one global strict/fast enum
one global supported/unsupported error model
persistent non-overlap proof tokens
public Mir types
public execution-layout selection
```

In particular, a global policy such as:

```text
fast
strict
```

would be underspecified.

For reduction, "fast" could change floating-point association.

For copy, numeric association is irrelevant while aliasing is critical.

For a future resampler, interpolation and edge semantics may matter instead.

Operation policy therefore belongs to the operation whose observable behavior
it controls.

## Planner terminology

The term `planner` may be used architecturally for the logic that combines:

```text
semantic request
    +
available capabilities
    +
required relational facts
    ->
compatible execution path
```

E5.0 does not introduce a `RasterPlanner` type.

For small operations the package-internal dispatcher itself is the planner.

A separate planner object becomes justified only if later operations need
materially reusable planning state, such as:

```text
multi-plane execution
multiple input rasters
neighborhood/halo requirements
tiling decisions
temporary-buffer requirements
parallel decomposition
device placement
```

## Empty operations

Empty operations remain semantic cases rather than execution-layout tricks.

Examples already established:

```text
empty sum
    -> additive identity

empty matching copy
    -> successful no-op
```

An empty operation should normally be resolved before forming execution pointers
or requiring capabilities that exist only for non-empty storage.

This rule prevents arbitrary metadata on empty views from forcing meaningless
execution classifications.

## Safety boundary

The operation layer should remain `@safe` wherever possible.

Trusted code is reserved for narrow boundaries where validated semantic facts
must be translated into operations the D type system cannot itself prove.

The checked-copy path is the current model:

```text
@safe dispatcher
    |
    v
validated source/target facts
    |
    v
single narrow @trusted boundary
    integer address relation
    overflow checks
    non-overlap proof
    memcpy
```

A specialized kernel is not itself justification for broadening `@trusted`.

## Performance policy

Execution specialization remains evidence-driven.

A new specialization should normally require:

```text
1. semantic contract is explicit
2. preconditions are representable and checked
3. reference implementation exists
4. code generation has been inspected when relevant
5. representative benchmark demonstrates value
6. DMD correctness path remains supported
7. LDC optimization remains measurable rather than assumed
```

E4 fixedLane4 and checked `memcpy` are the reference examples.

No architecture-independent size threshold should be introduced solely from one
development-machine benchmark.

## Public API boundary

E5 begins package-internal.

The eventual public raster operation API should express semantic intent, not
execution machinery.

A future public caller should not have to choose:

```text
Universal
Canonical
Contiguous
Mir Slice
memcpy
SIMD width
LLVM noalias
```

Those remain implementation concerns.

The public API may eventually expose semantic choices where they materially
change observable results, but E5.0 does not yet define their final shape.

## Module organization

E5.0 does not move the existing execution modules.

Current modules remain valid:

```text
internal/execution_layout.d
internal/mir_adapter.d
internal/mir_target_adapter.d
internal/scalar_kernels.d
internal/scalar_pointwise.d
internal/fixed_lane_kernels.d
internal/reduction_dispatch.d
internal/copy_dispatch.d
internal/target.d
```

A new directory or namespace such as `internal/operation/` should be introduced
only if additional operations demonstrate that the grouping improves dependency
direction and discoverability.

Avoiding a directory move in E5.0 keeps architecture work separate from
mechanical churn.

## Expected future operation families

The model should be capable of growing toward operations such as:

```text
pointwise transform
type conversion
clamp / scale / normalize
statistics
multi-band expressions
resampling
convolution
neighborhood filters
halo-aware processing
mosaic composition
quality-mask operations
```

These are not E5.0 implementation commitments.

They are checks that the model does not encode assumptions specific to sum or
copy.

## Dependency direction

The intended direction remains:

```text
public semantic API
        |
        v
package-internal operation contract
        |
        v
capability / relation analysis
        |
        v
operation-specific dispatch
        |
        v
execution adapters / kernels
```

Lower execution layers must not depend on a future public API.

Semantic raster types must not depend on Mir.

## E5 progression

The tentative progression after E5.0 is:

```text
E5.0
    define operation model and vocabulary

E5.1
    audit reduction and copy against the model
    identify genuinely repeated dispatcher mechanics

E5.2
    add only the smallest shared internal helpers justified by that audit

E5.3
    implement one additional operation through the model

E5.4
    reassess whether a stable public operation surface can be defined
```

E5.1 is intentionally an audit before refactoring.

The existence of similar-looking code is not by itself evidence that an
abstraction is useful.

## E5.1 reduction-versus-copy dispatcher audit

E5.1 audits the two existing production dispatchers before introducing any
shared operation-layer implementation.

The audited operations are:

```text
dispatchFloatToDoubleSum
tryCopyNonOverlappingContiguous1D
```

The audit deliberately compares semantic responsibilities rather than merely
similar source syntax.

### Exact common mechanism

Both dispatchers begin by asking the source `RasterView` for
`PlaneExecutionTraits`:

```text
RasterView
    |
    v
tryPlaneExecutionTraits
    |
    +-- invalid plane
    |
    `-- operation-specific continuation
```

This is the only meaningful identical dispatcher step.

No additional helper is justified for it.

`tryPlaneExecutionTraits` already is the shared capability-query abstraction.
Wrapping it again would either:

```text
return only bool + traits
    -> duplicate the existing API

or

construct an operation result
    -> become operation-specific
```

E5.1 therefore keeps the query directly in each dispatcher.

### Similar syntax that is not shared semantics

Both modules contain small success/failure construction helpers.

Reduction has:

```text
successfulSum(value)
failedSum(error)
```

Copy has:

```text
copySuccess()
copyFailure(error)
```

These are syntactically similar but semantically different.

The reduction result carries:

```text
operation error
double value
```

The copy result carries:

```text
operation error
```

Their failure domains also differ.

Reduction reports:

```text
invalidPlaneIndex
unsupportedExecution
invalidSemantics
```

Copy reports:

```text
invalidPlaneIndex
shapeMismatch
unsupportedExecution
overlapDetected
addressRangeUnrepresentable
```

A generic result or common success/failure helper would therefore remove useful
type information without eliminating meaningful complexity.

E5.1 does not introduce one.

### Empty handling is a convention, not a reusable implementation

Both operations resolve valid empty inputs before forming execution pointers or
demanding non-empty-only capabilities.

Their observable semantics remain operation-specific:

```text
empty reduction
    -> additive identity 0.0

empty matching copy
    -> successful no-op
```

The reusable concept is therefore the ordering rule:

> Resolve an operation's semantic empty case before requiring execution
> capabilities or physical pointers that are meaningful only for non-empty
> storage.

There is no common empty-operation helper.

### Capability use differs

Reduction consumes the full execution-layout classification.

Strict reduction selects among:

```text
Universal
Canonical
Contiguous 2D
flat Contiguous 1D
```

FixedLane4 requires:

```text
flat Contiguous 1D
```

Copy currently requires only:

```text
flat Contiguous 1D source
contiguous writable target
```

and does not dispatch over the full 2D layout enum.

The common abstraction therefore remains `PlaneExecutionTraits` itself. There
is no evidence for an additional generic capability-dispatch layer.

### Dispatch topology differs

Reduction dispatch topology is:

```text
validate plane
    |
    v
numeric semantic
    |
    +-- strict
    |     |
    |     `-- execution layout
    |
    `-- fixedLane4
          |
          `-- flat capability requirement
```

Copy dispatch topology is:

```text
validate plane
    |
    v
validate source/target shape
    |
    v
resolve empty no-op
    |
    v
require flat source capability
    |
    v
obtain source/target execution bases
    |
    v
prove pairwise physical relation
    |
    +-- overlap / unrepresentable -> failure
    |
    `-- proven non-overlap -> memcpy
```

A generic dispatcher would have to parameterize nearly every meaningful stage.
At that point it would be a framework around the operation-specific dispatcher
rather than a simplification of it.

E5.1 rejects that abstraction.

### Safety requirements differ

Reduction dispatch itself remains `@safe` and operates through already defined
execution adapters and kernels.

Checked copy uniquely requires a narrow trusted boundary for:

```text
pointer -> integer-address representation
range-end overflow checks
pairwise physical non-overlap proof
memcpy
```

Trusted execution is therefore not a common operation-layer phase that should
be represented in a generic planner.

It belongs only to operations whose concrete implementation requires it.

### Dependency structure differs

Reduction depends on:

```text
execution layout
Mir read adapters
scalar reduction kernels
fixed-lane reduction kernel
RasterView
```

Copy depends on:

```text
execution traits
RasterTargetPlane
RasterView
C memcpy
```

The small common dependency set is already represented by the lower raster
types and execution-trait API.

Creating another shared dispatcher module would add a dependency layer without
removing an existing one.

### E5.1 result

The audit finds a common conceptual pipeline but no new common production type
or helper worth introducing.

The result is:

```text
shared architectural vocabulary
    keep

RasterView / RasterTargetPlane
    keep

PlaneExecutionTraits
    keep as the shared capability representation

tryPlaneExecutionTraits
    keep as the shared capability-query boundary

operation-specific result types
    keep

operation-specific error enums
    keep

operation-specific dispatchers
    keep

generic operation result
    reject

generic execution policy
    reject

generic planner / dispatcher
    reject

new shared dispatcher helper
    not justified
```

Consequently E5.2 requires no production refactoring based on the current two
operations.

This is a deliberate outcome rather than a missing implementation: the
existing lower-level abstractions already capture the genuinely shared
mechanics.

The next useful test of the operation model is a third operation with different
requirements.

## E5.2 shared-helper decision

E5.1 found no new production helper justified by the existing reduction and
copy dispatchers.

The already existing shared mechanisms are sufficient:

```text
RasterView
RasterTargetPlane
PlaneExecutionTraits
tryPlaneExecutionTraits
```

No additional generic dispatcher, operation result, policy type, planner, or
capability wrapper is introduced.

E5.2 therefore has no production-code change.

This is intentional. A third operation is required before reconsidering which
mechanics are genuinely reusable.

## E5.3 third-operation test: exact ubyte-to-float conversion

The third operation used to test the E5 model is an exact pointwise conversion:

```text
RasterView!ubyte
        |
        v
numeric widening
        |
        v
RasterTargetPlane!float
```

### Semantic contract

For each logical source sample:

```text
target = cast(float) source
```

Every `ubyte` value is in the integer range:

```text
0 .. 255
```

and every value in that range is exactly representable as IEEE-754 binary32.

The initial operation therefore requires no:

```text
rounding policy
clamping policy
NaN policy
infinity policy
overflow policy
```

This makes the operation useful as a test of the operation architecture without
introducing unrelated conversion-policy complexity.

### Initial execution scope

The first implementation remains deliberately narrow:

```text
source sample
    ubyte

target sample
    float

source capability
    flat Contiguous 1D

target capability
    contiguous

shape
    source and target logical width/height must match

empty
    matching empty shapes succeed as a no-op
```

The source capability may be widened later only when a concrete need justifies
the additional dispatch paths.

### Source/target relation

Unlike same-type copy, the source and target byte extents differ.

For N logical samples:

```text
source bytes
    N * ubyte.sizeof

target bytes
    N * float.sizeof
```

A correct in-place traversal cannot generally be assumed when those physical
ranges overlap.

The initial operation therefore requires proven physical non-overlap before the
first target write.

Conceptually:

```text
sourceBase + sourceByteLength
targetBase + targetByteLength
        |
        v
checked physical relation
        |
        +-- overlap
        |      -> fail before write
        |
        +-- unrepresentable
        |      -> fail before write
        |
        `-- non-overlapping
               -> execute conversion kernel
```

This is intentionally the second real operation requiring a physical
source/target relation.

### Potential shared byte-range mechanism

E5.3 is the point at which factoring the physical range proof may become
justified.

The existing copy implementation currently combines:

```text
pointer-to-address conversion
byte-length arithmetic
range-end overflow validation
half-open interval comparison
copy execution
```

inside one narrow trusted helper.

For ubyte-to-float conversion the relation calculation is structurally similar,
but the successful action is not `memcpy` and the two ranges have different
byte lengths.

That suggests a possible lower-level abstraction:

```text
physicalByteRangeRelation(
    sourceBase,
    sourceByteLength,
    targetBase,
    targetByteLength
)
```

with a result conceptually equivalent to:

```text
overlapping
nonOverlapping
unrepresentable
```

However E5.3 must not introduce that helper merely from design symmetry.

The implementation sequence is:

```text
1. implement the conversion with its own complete checked path
2. verify safety and semantics
3. compare its relation logic with checked copy
4. factor only the truly identical relation mechanism
5. rerun both operation test suites
```

This preserves the E5 rule that abstraction follows demonstrated duplication.

### Reference execution

The first kernel is a scalar reference conversion.

Conceptually:

```text
foreach (i; 0 .. sampleCount)
    target[i] = cast(float) source[i];
```

The kernel itself operates after the dispatcher has established logical raster
shape, execution capability, and alias preconditions.

The flat execution kernel still defensively verifies that source and target
element counts are equal before the first write. This is a local execution
contract check; it does not replace the dispatcher's logical width/height
validation.

It does not decide:

```text
plane validity
logical raster shape validity
empty-operation semantics
alias policy
execution capability
```

Those remain dispatcher responsibilities.

### Numeric semantics

Unlike fixed-lane floating-point reduction, this conversion does not change an
arithmetic operation graph.

For every valid source sample:

```text
cast(float) ubyte
```

is exact.

A later SIMD implementation is therefore permitted only if it preserves the
same per-sample value mapping exactly.

No separate fast numeric semantic is required for this operation.

### E5.3a scalar reference kernel

The initial production reference kernel is:

```text
scalarConvertUbyteToFloatContiguous1D
```

Its execution contract is deliberately narrow:

```text
source
    flat Contiguous 1D const ubyte

target
    flat Contiguous 1D float

equal flat element count
    required

mismatched flat element count
    false before first target write

matching empty slices
    true

non-empty success
    target[i] = cast(float) source[i]
```

The kernel does not inspect `RasterView`, `RasterTargetPlane`, plane indices,
logical width/height, or physical alias relationships.

It introduces no trusted code and no numeric-policy type.

### E5.3b checked conversion dispatch

The package-internal conversion dispatcher is:

```text
tryConvertUbyteToFloatContiguous1D
```

Its validation order is:

```text
valid source plane
        |
        v
matching logical width/height
        |
        v
matching empty shape
        +-- yes -> successful no-op
        |
        v
flat Contiguous 1D source capability
        |
        v
source/target execution bases
        |
        v
representable physical byte ranges
        |
        v
pairwise non-overlap
        |
        +-- overlap / unrepresentable -> failure before write
        |
        `-- non-overlap
                |
                v
        scalar ubyte-to-float kernel
```

The source and target intervals deliberately use independent byte lengths:

```text
sourceByteLength = elementCount * ubyte.sizeof
targetByteLength = elementCount * float.sizeof
```

E5.3b intentionally keeps this physical-range calculation local to the
conversion operation even though checked copy contains structurally similar
logic.

This creates two concrete production use cases before E5.3c considers a shared
physical-byte-range abstraction.

Unlike checked copy, successful range classification performs no write.
Conversion executes only afterwards through the E5.3a scalar kernel.

The operation remains `@safe` except for the narrow physical-address
classification boundary, which converts pointers to integer addresses. That
boundary performs no dereference and no mutation.

### E5.3c shared physical-range arithmetic

With checked copy and checked ubyte-to-float conversion both implemented
independently, E5.3c identifies one genuinely repeated mechanism:

```text
integer start address
    +
byte length
    ->
overflow-safe half-open interval end

two intervals
    ->
overlapping / nonOverlapping / unrepresentable
```

The shared abstraction is intentionally placed *below* pointer handling:

```text
classifyByteAddressRanges(
    firstStart,
    firstByteLength,
    secondStart,
    secondByteLength
)
```

It accepts only `size_t` integer addresses and byte lengths.

This is an important safety boundary decision.

The shared classifier is:

```text
@safe
pure
nothrow
@nogc
```

and performs:

```text
no pointer conversion
no pointer arithmetic
no dereference
no mutation
no memcpy
```

Pointer-to-integer conversion remains inside each operation's existing narrow
trusted boundary.

For checked copy that trusted boundary still owns the complete critical
sequence:

```text
source/target pointers
        |
        v
pointer -> integer addresses
        |
        v
shared safe range classification
        |
        +-- overlap / unrepresentable -> failure
        |
        `-- non-overlap
                |
                v
              memcpy
```

Thus E5.3c does not weaken the E4.3b guarantee that the proof and `memcpy`
remain coupled inside one trusted function.

For conversion:

```text
source/target pointers
        |
        v
pointer -> integer addresses
        |
        v
shared safe range classification
        |
        v
relation returned to @safe dispatcher
        |
        `-- non-overlap -> typed scalar conversion kernel
```

The two operations also retain their own element-to-byte calculations because
their semantics differ:

```text
checked copy
    one T.sizeof
    same source/target byte length
    successful relation immediately permits memcpy

ubyte -> float conversion
    ubyte.sizeof and float.sizeof
    different source/target byte lengths
    successful relation permits a typed conversion kernel
```

E5.3c therefore extracts only the arithmetic that is demonstrably identical.

It does not introduce:

```text
generic operation results
generic alias policy
persistent proof tokens
shared pointer ownership
shared trusted pointer classifier
generic execution dispatcher
```

### E5.3d ubyte-to-float code-generation audit

The E5.3a scalar conversion kernel was compiled directly with:

```text
LDC 1.41.0
LLVM 19.1.7
x86-64
Skylake
-O3
-release
-enable-inlining
-mcpu=native
```

No handwritten SIMD or fast-math semantics were introduced.

LLVM reports:

```text
vectorization width: 8
interleaved count: 4
```

The native vector loop lowers the exact integer-to-float conversion to four
independent eight-sample groups:

```text
vpmovzxbd
vpmovzxbd
vpmovzxbd
vpmovzxbd

vcvtdq2ps
vcvtdq2ps
vcvtdq2ps
vcvtdq2ps

vmovups
vmovups
vmovups
vmovups
```

Thus one main-loop iteration converts 32 samples while preserving the exact
`ubyte -> float` operation semantics.

A handwritten AVX2 conversion kernel is therefore not justified by current
evidence.

#### Runtime alias versioning

The audit also found an important missed cross-layer optimization opportunity.

Before entering the vector loop LLVM emits a runtime memory-conflict check
equivalent to:

```text
targetStart < sourceEnd
    &&
sourceStart < targetEnd
```

If that condition indicates possible overlap, execution falls back to the
scalar path.

Only after this check does LLVM attach the alias metadata used by the vector
body.

This check is semantically redundant for calls made through the E5.3b
dispatcher because that dispatcher has already established pairwise physical
non-overlap before invoking the conversion kernel.

The current architecture therefore loses an established relational fact at
the dispatcher-to-kernel boundary:

```text
dispatcher
    proves non-overlap
        |
        v
scalar conversion kernel
    has no representation of that proof
        |
        v
LLVM independently emits runtime alias versioning
```

This does not affect correctness. It can affect generated code and runtime
cost.

#### E5.3d decision

Current evidence supports:

```text
LLVM auto-vectorization       KEEP
handwritten AVX2              DO NOT ADD
fast-math                     NOT RELEVANT
manual vector-width policy    DO NOT ADD
runtime alias guard           INVESTIGATE
```

The next experiment should isolate whether communicating the already-proven
non-overlap fact to LDC/LLVM removes the redundant runtime memory check and
whether doing so produces a measurable benefit.

Such an experiment must not weaken the existing safety architecture:

```text
no caller-provided unchecked alias assertion
no persistent public proof token
no uniqueness claim on RasterTargetPlane
no compiler-specific attribute in the public API
```

Any compiler-specific alias specialization remains an internal execution
detail and requires code-generation plus performance evidence before production
adoption.

### E5.3e alias-information performance audit

E5.3d established that the scalar `ubyte -> float` production kernel is already
auto-vectorized by LDC/LLVM on the tested Skylake system.

LLVM nevertheless emits runtime alias versioning because the pairwise
non-overlap fact established by the dispatcher is not represented at the
kernel boundary.

A controlled code-generation experiment compared two otherwise equivalent
raw-pointer kernels:

```text
ordinary source/target pointers
    -> runtime vector.memcheck
    -> vectorized loop

LDC @restrict source/target pointers
    -> LLVM noalias parameters
    -> no vector.memcheck
    -> same vectorized loop
```

The restricted function therefore proves that communicating non-overlap to LLVM
can eliminate the redundant runtime memory check.

This establishes a code-generation opportunity, but not by itself a production
optimization requirement.

#### Performance experiment

The current Mir-slice production kernel, an unknown-alias raw-pointer kernel,
and an `@restrict` raw-pointer kernel were benchmarked with LDC `-O3`,
`-release`, `-mcpu=native`.

The benchmark used:

```text
9 rounds per process
9 independent processes
CPU affinity to one logical CPU
rotated implementation order
median within each process
paired ratios across processes
```

The controlled comparison for alias information is:

```text
raw unknown alias
    versus
raw @restrict
```

The Mir result is retained as production context but contains additional ABI,
slice-construction, length-check, and code-layout differences.

Representative paired median results were:

```text
samples     unknown/restrict     median delta

31          0.8456               -3.098 ns
32          1.1697                0.767 ns
33          1.5177                2.461 ns
64          1.0796                0.495 ns
128         1.0634                0.791 ns
256         1.0755                1.225 ns
1024        1.1739               10.774 ns
4096        0.9970               -1.033 ns
65536       1.0014               15.864 ns
1048576     1.0045              914.734 ns
4194304     1.0064            11627.125 ns
```

The small-size results must not be interpreted as the cost of one fixed alias
check alone.

Below and around the vectorization threshold LLVM generates different scalar,
tail, and control-flow structures. The especially large relative differences
at 32 and 33 samples therefore describe the complete generated execution path,
not merely the address comparisons of `vector.memcheck`.

The isolated result at 1024 samples is reproducible enough to be noteworthy,
but it does not continue monotonically with increasing raster size and cannot
be attributed solely to the fixed range check.

#### Raster-scale interpretation

At raster-oriented sizes the advantage disappears into the cost and variability
of the conversion itself.

For 65536 samples, corresponding to a 256 x 256 plane:

```text
unknown/restrict = 1.0014
ratio MAD        = 0.0010
```

The measured difference is approximately 0.1 percent.

At 1048576 samples:

```text
unknown/restrict = 1.0045
ratio MAD        = 0.0045
```

The observed effect is of the same order as run-to-run dispersion.

At 4194304 samples:

```text
median unknown/restrict = 1.0064
ratio MAD               = 0.0165
```

Individual process medians ranged across both sides of unity:

```text
0.9824
0.9913
1.0282
0.9940
1.0342
0.9911
1.0228
1.0330
1.0064
```

The sign reversal across independent runs demonstrates that the large-buffer
difference is dominated by effects other than the one-time alias guard, such
as cache, memory-system, frequency, scheduling, or code-placement variability.

#### E5.3e decision

The current evidence supports:

```text
LLVM auto-vectorization       KEEP
Mir execution kernel          KEEP
runtime alias versioning      ACCEPT
handwritten AVX2              DO NOT ADD
production @restrict path     DO NOT ADD
public alias assertion        DO NOT ADD
persistent non-overlap token  DO NOT ADD
```

The already-proven non-overlap fact can technically be communicated to LLVM
through a compiler-specific `noalias` contract, but the measured benefit is not
material at representative raster block sizes.

Introducing such a contract would strengthen the semantic precondition of a
low-level function: an incorrect call could make compiler optimizations
invalid rather than merely select a slower path.

That additional proof burden is not justified by the observed performance.

The existing checked dispatcher therefore remains the preferred design:

```text
semantic validation
    |
pairwise physical non-overlap proof
    |
safe scalar semantic kernel
    |
LLVM runtime alias versioning
    |
auto-vectorized execution
```

The small redundant runtime check is accepted as the cost of retaining the
simpler and safer kernel contract.

#### E5.3 outcome

The third-operation exercise has now provided evidence for all intended E5
questions.

It produced:

```text
exact ubyte -> float semantic conversion
scalar reference kernel
checked operation-specific dispatcher
explicit empty and shape semantics
checked pairwise non-overlap
shared @safe physical byte-range arithmetic
automatic SIMD code generation
evidence against premature noalias specialization
```

It also validated the E5.0 architectural rule that common machinery should be
extracted only after duplication is demonstrated by real operations.

No broader generic operation hierarchy, execution-policy framework, alias-proof
token, or public compiler-specific specialization is justified at this stage.

The next phase is E5.4: reassess the public raster-operation surface using the
three implemented operation families as evidence.

### Expected E5.3 implementation stages

```text
E5.3a
    scalar flat-contiguous ubyte-to-float reference kernel

E5.3b
    checked operation dispatcher
    shape / empty / capability / non-overlap semantics

E5.3c
    compare physical-range logic with checked copy
    factor a shared helper only if the duplication is exact

E5.3d
    inspect LDC code generation and benchmark
    add specialization only if evidence supports one

E5.3e
    re-audit reduction, copy, and conversion against the E5 model
```

The operation remains package-internal throughout E5.3.

It is not yet evidence for a public conversion API.

## E5.0 decision

The raster engine uses a common conceptual operation pipeline but retains
operation-specific contracts and dispatchers.

The stable abstraction at this stage is:

```text
semantic request
        |
        v
validated operands
        |
        v
execution capabilities
        |
        v
operation-specific relational facts
        |
        v
compatible kernel selection
        |
        v
execution
```

The stable abstraction is therefore currently an architectural model, not a
generic runtime type hierarchy.

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

## E5.4 public raster-operation surface

E5.0 through E5.3 established the internal operation model using three
concrete operation families:

```text
reduction
    RasterView -> scalar value

copy
    RasterView -> writable target

conversion
    RasterView!ubyte -> writable target!float
```

E5.4 now asks a different question:

```text
Which of these semantics are stable enough to expose publicly
without freezing internal execution mechanisms into the API?
```

The answer must be derived from the implemented operations rather than from a
generic operation hierarchy designed in advance.


### E5.4a current public-surface audit

The current `imagery.raster` package publicly exposes:

```text
isRasterSampleType

OwnedByteResource
tryAdoptMallocResource

PlaneByteLayout

OwnedRasterImportError
OwnedRasterImportResult
OwnedRasterResourceDisposition
tryImportOwnedRaster

PlaneDescriptor
Region2D
RasterView
RasterLease
```

It does not expose:

```text
Mir Slice types
Universal / Canonical / Contiguous execution layouts
PlaneExecutionTraits
RasterTargetPlane
physical-range classification
reduction dispatch
copy dispatch
conversion dispatch
memcpy specialization
compiler noalias / restrict machinery
```

This boundary is correct and must be preserved.

The execution-surface compile-negative tests independently verify that the
current reduction, copy, conversion, and physical-range machinery cannot be
imported from modules outside `imagery.raster`.

No existing internal operation type should therefore be made public merely by
changing its visibility.


### Writable semantic gap

The current writable type is:

```text
RasterTargetPlane!T
```

It is deliberately package-internal.

Its current capability is:

```text
single plane
contiguous storage
width / height
flat element count
non-owning borrow
no uniqueness guarantee
no non-alias guarantee
```

This is useful as an execution capability.

It is not a sufficient public writable raster abstraction.

A semantic public writable raster view must not imply that writable raster
storage is necessarily:

```text
single-plane
flat
contiguous
positive-stride
represented by one D slice
```

Those are execution properties, not raster semantics.

Consequently:

```text
DO NOT make RasterTargetPlane public
DO NOT make tryBorrowContiguousTarget public
DO NOT use RasterTargetPlane as the public destination type
```

Future operation dispatch may derive a `RasterTargetPlane` or another
specialized writable capability internally from a more general semantic
writable view.


### Reduction public-surface audit

Reduction differs from copy and conversion because it requires no writable
destination:

```text
RasterView!float
    ->
double
```

This means reduction is not blocked by the missing writable raster abstraction.

However, the current dispatcher is still not itself a suitable public API.

Its current semantic selector contains:

```text
strict
fixedLane4
```

`strict` describes externally meaningful numeric behavior.

`fixedLane4` describes the concrete evaluation graph of the current optimized
kernel. The lane count is an implementation-shaped name and should not become
a general public raster policy accidentally.

Likewise:

```text
unsupportedExecution
```

is an internal dispatch outcome caused by the currently available execution
capabilities. It is not an inherent mathematical failure of summation.

A public reduction operation should therefore not directly export:

```text
SumReductionSemantics
FloatToDoubleSumDispatchError
FloatToDoubleSumResult
dispatchFloatToDoubleSum
```

The strict reduction semantics are potentially public-ready, but E5.4a does
not yet introduce them.

Public naming, result semantics, and numeric-policy vocabulary should be
decided independently of the current dispatcher implementation.


### Copy public-surface audit

The current checked copy operation is intentionally named:

```text
tryCopyNonOverlappingContiguous1D
```

That name accurately describes the internal specialization.

It should not become the semantic public copy operation.

A public raster copy must define what overlap means at the semantic level.

Possible public semantics include, for example:

```text
overlap is supported
overlap is rejected as a semantic error
source is logically snapshotted before writes
```

That decision must not be inferred from the requirements of the current
`memcpy` specialization.

Likewise, the following current errors are partly execution details:

```text
unsupportedExecution
addressRangeUnrepresentable
```

and should not automatically become permanent public copy errors.

The public contract must be designed first; internal dispatch can then choose
between scalar traversal, memcpy-like specialization, overlap-safe execution,
or future kernels without changing that contract.


### Conversion public-surface audit

The E5.3 conversion has a stable numeric semantic core:

```text
ubyte -> float

0 .. 255
    ->
exact IEEE-754 binary32 value
```

The current implementation nevertheless accepts an internal contiguous
`RasterTargetPlane!float` and can report `unsupportedExecution`.

Therefore the implemented conversion proves the operation architecture, but
does not yet define a general public conversion API.

In particular, one concrete conversion is not enough evidence for a generic
public abstraction such as:

```text
convertRaster!(Source, Target)
GenericConversionPolicy
GenericConversionResult
```

Such generalization remains premature.

Once a public writable raster view exists, the exact `ubyte -> float`
operation can be reconsidered as one semantic conversion without exposing its
current flat-contiguous specialization.


### Public errors must describe semantics, not implementation coverage

The internal dispatchers correctly expose errors such as:

```text
unsupportedExecution
addressRangeUnrepresentable
```

to package-internal callers.

That does not imply those values belong in public operation results.

A stable public semantic operation should generally not fail merely because
the current fastest specialization does not support a layout if a correct
general implementation can exist.

The desired layering is:

```text
public semantic operation
    |
    v
validate semantic request
    |
    v
derive execution capabilities
    |
    +-- specialized kernel when supported
    |
    `-- correct general fallback when available
```

`unsupportedExecution` therefore remains an internal implementation state
unless an operation is deliberately specified to support only a restricted
class of raster storage.


### E5.4a decision

Current evidence supports:

```text
public RasterView                         KEEP
public RasterLease                        KEEP

internal RasterTargetPlane                KEEP INTERNAL
internal execution layouts                KEEP INTERNAL
internal Mir adapters                     KEEP INTERNAL
internal physical-range machinery         KEEP INTERNAL

export current reduction dispatcher       NO
export current copy dispatcher            NO
export current conversion dispatcher      NO

generic public operation hierarchy        DO NOT ADD
generic public conversion policy          DO NOT ADD
public alias-proof token                   DO NOT ADD
```

No production visibility changes are justified by E5.4a.


### Required writable abstraction

Before source-to-target raster operations can become public, the raster layer
needs a semantic writable borrowing abstraction.

The working architectural role is:

```text
public semantic writable raster view
    |
    | validate topology, reachability and lifetime
    v
internal writable execution capabilities
    |
    +-- RasterTargetPlane when flat contiguous
    +-- future canonical writable plane
    `-- future universal writable plane
```

The public writable view should ultimately be able to represent the same
logical raster concepts as `RasterView`:

```text
multiple logical planes
Region2D geometry
descriptor-space coordinates
signed row stride
signed sample stride
empty regions
borrowed lifetime
```

while additionally providing mutable sample access.

It must not imply:

```text
unique ownership
source/target non-aliasing
contiguous layout
one-plane storage
provider-tile identity
cache-block identity
```

Pairwise relations such as source/target overlap remain operation-local facts.


### Naming is not yet fixed

E5.4a deliberately does not commit to a public type name.

Candidates such as:

```text
MutableRasterView
RasterWriteView
WritableRasterView
```

describe approximately the required role, but naming should follow the
lifetime, descriptor, ownership, and read/write contract audit.

The type should be designed from semantic requirements rather than by promoting
`RasterTargetPlane`.


### E5.4b writable-raster prerequisite audit

The retained raster, descriptor, ownership, and lifetime layers were audited
before introducing a public writable raster view.

The audit separates three independent questions:

```text
where is the storage?
who keeps it alive?
may this API write through it?
```

The first two are already represented.

The third is not.


#### PlaneDescriptor remains access-neutral

`PlaneDescriptor` currently stores:

```d
const(void)* base;
ptrdiff_t rowStrideElements;
ptrdiff_t sampleStrideElements;
```

Its existing contract explicitly states that the descriptor is access-neutral:

```text
PlaneDescriptor describes a physical raster address and traversal geometry.
It does not itself grant write permission.
```

This is the correct abstraction.

`const(void)*` in this type must therefore not be interpreted as meaning that
the underlying allocation is intrinsically read-only.

Conversely, changing it to `void*` would conflate:

```text
physical address metadata
```

with:

```text
permission to mutate storage
```

E5.4b therefore decides:

```text
PlaneDescriptor.base             KEEP const(void)*
PlaneDescriptor                  KEEP access-neutral
public descriptor semantics      DO NOT add writability
```

A writable raster capability must carry write permission separately.


#### Retained backing still owns the physical resources

`RasterBacking!T` retains:

```text
ResourceEntry[]
PlaneDescriptor[]
resource metadata allocation
descriptor metadata allocation
Region2D
```

`ResourceEntry` currently contains:

```d
void* base;
size_t byteLength;
void* releaseContext;
ReleaseFn releaseFn;
```

The backing therefore retains the raw physical resource address required for
ownership and release.

This means the current implementation has not physically lost the original
resource address when a `RasterView` is created.

However:

```text
ResourceEntry.base is void*
```

does not by itself establish the semantic claim:

```text
the resource may be mutated through a public writable raster API
```

The raw pointer representation exists inside an ownership/release layer and is
reachable only through package-internal or system/trusted construction paths.

A raw mutable pointer and a public write capability are not equivalent.


#### RasterLease currently represents lifetime, not write permission

`RasterLease!T` contains the retained `SafeRefCounted` backing owner.

Its public view operation is:

```text
RasterLease.view()
    ->
RasterView!T
```

The implementation uses the existing borrow chain:

```text
RasterLease
    |
    v
SafeRefCounted.borrow
    |
    v
makeViewFromBacking(return ref RasterBacking)
    |
    v
RasterView
```

The resulting view cannot outlive the lease.

This lifetime model is already suitable as a template for a future writable
borrow.

But `RasterLease` currently has no semantic state that says:

```text
this backing is write-capable
```

and no API such as:

```text
writeView()
mutableView()
```

should be added until that capability has a defined provenance.


#### Lifetime is not the missing mechanism

The existing read-view compile-negative tests already verify that:

```text
a RasterView cannot escape its RasterLease
a child ROI cannot outlive its parent borrow
a borrowed view cannot be stored globally
```

The internal writable `RasterTargetPlane` provides complementary evidence.

It safely borrows a caller-owned `T[]` with `return scope`, and the
compile-negative tests reject:

```text
returning a target backed by local storage
returning a Mir target backed by local storage
storing the target globally
```

Therefore E5.4 does not need a new lifetime model merely because the view is
writable.

The existing DIP1000 borrowing techniques are sufficient evidence for the
required lifetime shape.

The unresolved issue is access permission, not lifetime.


#### Writable does not imply unique

A future writable raster view must continue the rule already established by
`RasterTargetPlane`:

```text
writable != unique
writable != non-aliasing
```

A write-capable view means only:

```text
writes through this capability are permitted
```

It does not mean:

```text
no other view references the same storage
no read view exists
no second writable view exists
source and destination do not overlap
```

`RasterLease` itself is copyable and multiple leases may retain the same
backing.

Consequently no public writable-view design should pretend to provide
Rust-style exclusive borrowing unless a separate mechanism actually proves
that property.

Pairwise source/target overlap remains an operation-local relation.


#### Why void* is not sufficient writable provenance

The current retained resource representation needs `void*` for raw ownership
and release callbacks.

That fact is deliberately weaker than a semantic writable-storage invariant.

Future resources may include, for example:

```text
read-only memory mappings
externally owned read-only storage
provider buffers with restricted access
mixed-resource raster backing
```

The public raster model should not have to reinterpret such storage as writable
merely because the release layer uses a raw pointer representation.

Therefore this transformation is not justified:

```text
ResourceEntry.base
    |
    | cast
    v
public mutable T*
```

without an independently established write-capability invariant.


#### Writable provenance must be retained explicitly

Before a `RasterLease` can issue a public writable raster borrow, construction
must retain enough information to prove that each reachable target sample is
backed by storage for which mutation is permitted.

Conceptually the missing relation is:

```text
physical retained resource
    +
write-capability provenance
    +
validated raster layout
    ->
writable raster borrow
```

The write capability must originate at a boundary that is entitled to make
that claim.

Examples include:

```text
owned malloc-compatible mutable allocation
mutable caller-owned storage borrow
read-write memory mapping
provider API explicitly granting writable access
```

A read-only resource must not acquire writability merely because an internal
pointer can technically be cast.


#### Access granularity remains an open design choice

E5.4b does not yet choose how writable provenance is represented.

At least three models are possible.

##### Backing-wide access state

```text
RasterBacking
    access = readOnly | readWrite
```

Advantages:

```text
simple
cheap
easy writeView decision
```

Disadvantage:

```text
too coarse if one backing can eventually contain resources with different
access capabilities
```

##### Per-resource access state

Conceptually:

```text
ResourceEntry
    physical byte range
    release policy
    access capability
```

A writable view can then be created only when every physical resource needed by
the requested planes/region permits writes.

Advantages:

```text
supports mixed-resource backing
models physical capability where it originates
does not change PlaneDescriptor semantics
```

Cost:

```text
writable-view construction must resolve descriptor footprints against retained
resources
```

That work occurs at capability-construction time rather than in hot pixel loops.

##### Separate writable lease capability

Another possibility is a distinct retained capability such as conceptually:

```text
RasterLease
WritableRasterLease
```

or an equivalent access-parameterized retained type.

This provides stronger static distinction but risks duplicating ownership APIs
and complicating conversion between read and write capabilities.

E5.4b does not select this model yet.


#### Backing-wide assumptions should not be introduced accidentally

The current public owned-raster import happens to start from an
`OwnedByteResource` whose existing malloc adoption path accepts mutable
storage.

That implementation fact is insufficient reason to define every
`RasterLease!T` permanently as writable.

`RasterLease` is an architectural retained-backing abstraction and future
providers should be able to participate without manufacturing write permission.

Therefore:

```text
current malloc storage is mutable
```

does not imply:

```text
RasterLease means writable retained raster
```

unless that invariant is deliberately adopted for the whole library.

E5.4b does not adopt such an invariant.


#### Mutable descriptor duplication is not justified

One possible design would introduce:

```text
MutablePlaneDescriptor
```

containing the same strides plus a mutable pointer.

E5.4b finds no evidence that this should become a public peer of
`PlaneDescriptor`.

The physical geometry is identical for reads and writes:

```text
descriptor-space origin
row stride
sample stride
```

Only the access capability differs.

Duplicating the public geometry type would therefore risk allowing the read and
write representations of the same raster to drift apart.

The preferred architectural direction is:

```text
PlaneDescriptor
    describes physical geometry

separate retained access provenance
    establishes whether writes are permitted

WritableRasterView
    combines validated geometry with a write capability
```

How that combination is represented internally remains an E5.4c question.


#### Expected writable-view lifetime shape

Subject to establishing writable provenance, the eventual borrow topology can
mirror the existing read view:

```text
retained backing
        |
        +------------------------+
        |                        |
        v                        v
RasterView!T             WritableRasterView!T
read capability          write capability
        |                        |
        v                        v
read execution           writable execution
capabilities             capabilities
                                 |
                                 +-- RasterTargetPlane
                                     when contiguous
```

Both view types remain:

```text
non-owning
lifetime-bound
region-aware
multi-plane capable
signed-stride capable
```

The writable side adds only permission to mutate reachable samples.

It does not add ownership or uniqueness.


#### E5.4b decisions

The prerequisite audit supports:

```text
PlaneDescriptor                         KEEP
PlaneDescriptor.base const(void)*       KEEP
RasterBacking ownership model           KEEP
RasterLease read view                    KEEP

RasterTargetPlane                        KEEP INTERNAL

existing DIP1000 borrow strategy         REUSE
writable != unique                       PRESERVE
overlap remains operation-local          PRESERVE

RasterLease.writeView                    DO NOT ADD YET
public WritableRasterView                DO NOT ADD YET
public MutablePlaneDescriptor             DO NOT ADD
cast const descriptor base to writable    DO NOT USE AS PROOF
```

The retained representation contains enough physical information to support
future writable execution, but the semantic write-capability provenance is not
currently represented strongly enough to expose it safely.

That is the only new prerequisite identified by E5.4b.


#### E5.4b result

The original concern that writable operations might require a redesign of
raster ownership or lifetime management is not supported by the audit.

The narrower result is:

```text
ownership       sufficient
lifetime        sufficient
geometry        sufficient
execution model sufficient

write-access provenance
    missing
```

Therefore the next design step must solve access provenance before defining the
public writable view.

### E5.4c retained write-access provenance

E5.4b identified one missing prerequisite for a public writable raster view:

```text
ownership       sufficient
lifetime        sufficient
geometry        sufficient
execution model sufficient

write-access provenance
    missing
```

E5.4c decides where that provenance belongs.


#### Candidate 1: backing-wide access state

The simplest representation would attach one mode to the complete retained
backing:

```text
RasterBacking
    access = readOnly | readWrite
```

This makes writable-view creation cheap:

```text
if backing.access == readWrite
    writable view may be issued
```

However the model is too coarse.

`RasterBacking` already supports multiple physical `ResourceEntry` objects and
multiple logical planes. Future raster sources may legitimately combine
resources whose access capabilities differ.

Examples include:

```text
read-only memory-mapped source plane
mutable scratch plane
provider-owned read-only calibration plane
mutable output plane
```

A backing-wide flag would either:

```text
reject useful mixed backing
```

or:

```text
grant write permission more broadly than the physical resources justify
```

Therefore:

```text
backing-wide write mode
    REJECT
```


#### Candidate 2: separate writable lease type

A second possibility is to encode access statically in the retained lifetime
capability:

```text
RasterLease!T
WritableRasterLease!T
```

or through an access template parameter.

This has an attractive property:

```text
a writable lease is visibly different in the type system
```

but it also introduces substantial costs.

The current lease represents one concept:

```text
retain this raster backing for as long as borrowed views need it
```

Duplicating that capability would duplicate or parameterize:

```text
ownership transitions
reference counting
copy behavior
import results
construction paths
view creation
lifetime tests
```

without solving uniqueness.

A writable lease could still be copied, and read and writable capabilities
could still coexist for the same retained allocation unless an additional
exclusive-borrow mechanism were introduced.

Such exclusivity is neither required by the current raster operations nor
provided by the existing D lifetime model.

Therefore:

```text
separate public writable lease
    REJECT FOR CURRENT REQUIREMENTS
```

A future ownership model requiring exclusive mutation could revisit this
decision independently.


#### Candidate 3: per-resource access capability

The selected model attaches access provenance to each retained physical
resource.

Conceptually:

```text
ResourceEntry
    base
    byteLength
    releaseContext
    releaseFn
    access
```

with an access state equivalent to:

```text
readOnly
readWrite
```

The exact internal enum name is not fixed by this design section.

The important invariant is:

```text
readOnly must be the conservative/default state
```

A resource becomes `readWrite` only when the boundary introducing that resource
is entitled to make that claim.


#### Why resource granularity matches the architecture

Write permission is a property of physical storage, not raster geometry.

The existing separation is already:

```text
ResourceEntry
    physical retained byte range
    ownership/release

PlaneDescriptor
    physical origin
    row/sample traversal geometry

Region2D
    resident logical extent
```

Adding access capability to the physical-resource side preserves that
separation:

```text
ResourceEntry
    storage capability

PlaneDescriptor
    geometry

RasterView / WritableRasterView
    semantic access capability
```

No mutable counterpart of `PlaneDescriptor` is required.


#### Existing validation provides the required geometric relation

Backing validation already proves for every non-empty plane that every reachable
sample lies entirely inside at least one retained physical resource.

Conceptually:

```text
PlaneDescriptor + Region2D
    |
    v
reachable physical footprint
    |
    v
contained by a ResourceEntry
```

Writable certification can extend the same relation to:

```text
PlaneDescriptor + Region2D
    |
    v
reachable physical footprint
    |
    v
contained by at least one ResourceEntry
whose access capability is readWrite
```

This is stronger than merely checking whether:

```text
descriptor.base
```

falls inside writable storage.

Negative strides, sample strides, row padding, and complete `T` sample width
must continue to participate in the footprint proof.


#### A plane is not assembled from partial resource coverage

The current validation model tests whether one retained resource contains the
complete reachable footprint of a plane.

It does not establish safety by combining fragments of several resources.

Writable capability should retain the same invariant:

```text
for each writable non-empty plane
there exists at least one write-capable ResourceEntry
that contains its complete reachable footprint
```

This keeps read and write reachability semantics aligned.

If a future storage model genuinely requires one logical plane to span several
independent resources, that requires a different raster representation rather
than weakening this invariant silently.


#### Overlapping retained resources do not create write permission

The existence of more than one retained resource containing the same physical
range must not make access ambiguous.

Writable certification is existential only with respect to a resource whose
provenance actually grants writes:

```text
exists containing resource
    with access == readWrite
```

A read-only resource entry covering the same address range does not revoke a
valid independent read-write capability, and a raw pointer overlap does not
manufacture one.

Ownership correctness for overlapping retained resources remains a separate
construction concern.

E5.4c does not use address overlap itself as access provenance.


#### Access provenance originates at resource introduction

The access state must be established where raw storage first enters the raster
ownership system.

Examples:

```text
malloc allocation
    -> readWrite

mutable caller-owned storage
    -> readWrite

read-write mmap
    -> readWrite

read-only mmap
    -> readOnly

provider buffer documented read-only
    -> readOnly

provider buffer documented writable
    -> readWrite
```

The boundary making this decision may be `@system` or `@trusted` as required by
the external ownership/access contract.

Once retained, downstream raster code consumes the stored capability rather
than reconstructing writability from pointer types.


#### Current malloc adoption

The existing malloc-adoption path receives a mutable `void*` allocation whose
ownership is transferred into `OwnedByteResource`.

For that specific boundary the library is entitled to retain:

```text
readWrite
```

because malloc-compatible owned storage is mutable by construction.

This does not redefine `OwnedByteResource` itself as intrinsically writable.

Other future adoption paths may produce:

```text
readOnly
```

resources.

Therefore the stable rule is:

```text
resource introduction determines access capability
```

not:

```text
owned resource implies writable
```


#### OwnedByteResource carries provenance through ownership transfer

`OwnedByteResource` is the transactional owner before retained construction.

Its internal raw resource state must preserve the access capability together
with:

```text
base
byteLength
releaseContext
releaseFn
```

Ownership transfer must not change access:

```text
external adoption
    |
    v
OwnedByteResource
    |
    v
ResourceEntry
    |
    v
RasterBacking

access capability remains unchanged
```

Thus write provenance survives the same transactional commit process already
used for release obligations.


#### Safe default behavior

Any default-initialized or incompletely established resource metadata must not
accidentally grant writes.

The access representation should therefore satisfy:

```text
.init == no write capability
```

Conceptually:

```text
enum ResourceAccess : ubyte
{
    readOnly,
    readWrite
}
```

would satisfy that requirement when `readOnly` is the zero value.

The exact production name remains an implementation detail until E5.4c is
implemented.


#### Read views ignore write capability

`RasterView!T` remains valid for either resource state:

```text
readOnly  -> RasterView permitted
readWrite -> RasterView permitted
```

No changes are required to:

```text
PlaneDescriptor
RasterView
read execution adapters
reduction operations
```

This is an important compatibility property of the selected model.


#### Writable views require positive certification

A future writable view is not created merely because the backing exists.

Its construction must prove:

```text
for every requested non-empty plane:
    complete reachable footprint
    is contained in a retained readWrite resource
```

Only after that proof may the writable view establish a trusted mutable pointer
boundary.

Conceptually:

```text
RasterBacking
    |
    | certify requested region/planes writable
    v
WritableRasterView
    |
    | trusted execution pointer formation
    v
T*
```

The cast from access-neutral descriptor address to `T*` is therefore a
consequence of an already-established capability.

It is not itself the proof.


#### Empty writable views

Empty raster regions reach no samples.

They therefore require no physical writable sample storage, matching the
existing read-view semantics.

A future writable-view constructor may therefore permit geometrically valid
empty regions without requiring a containing write-capable resource.

It must still preserve:

```text
plane topology
Region2D dimensions
borrow lifetime
```

and must form no mutable pixel pointer for the empty case.


#### Mixed-access backing

Per-resource provenance permits a retained backing such as:

```text
resource 0     readWrite
resource 1     readOnly
resource 2     readWrite
```

A writable capability may be created only for planes whose complete physical
footprints are certified by write-capable resources.

This creates an important design consequence for E5.4d:

```text
writability may be plane-specific
```

A single boolean:

```text
backing.isWritable
```

is therefore not a sufficient long-term semantic model.


#### Whole-view versus selected-plane writable capabilities

E5.4c does not yet decide whether the first public writable view must require:

```text
all planes writable
```

or whether it can represent:

```text
a selected writable subset of planes
```

For the initial E5.4d design, the simpler invariant is preferred:

```text
every plane represented by WritableRasterView must be writable
```

A caller can obtain a narrower writable view/capability rather than carrying
read-only planes inside a type whose semantic promise is writable.

The exact subsetting API belongs to E5.4d.


#### No uniqueness or alias guarantee

Per-resource access provenance establishes only:

```text
writes are permitted
```

It does not establish:

```text
exclusive ownership
unique borrowing
non-overlap with another view
non-overlap between logical planes
non-overlap between source and target
```

Those remain separate facts.

In particular:

```text
WritableRasterView
    !=
NoAliasRasterView
```

Copy and conversion dispatch must continue to establish source/target physical
relations independently.


#### Selected architecture

The retained raster architecture becomes conceptually:

```text
               retained backing
                     |
          +----------+----------+
          |                     |
          v                     v
   ResourceEntry[]       PlaneDescriptor[]
          |                     |
   physical storage          geometry
   ownership/release
   access provenance
          |                     |
          +----------+----------+
                     |
          +----------+----------+
          |                     |
          v                     v
      RasterView         WritableRasterView
      read access        certified write access
```

`PlaneDescriptor` remains shared geometric metadata.

`ResourceEntry` carries the physical capability.


#### E5.4c decisions

Current evidence supports:

```text
write-access granularity                PER RESOURCE

backing-wide writable flag              DO NOT ADD
separate WritableRasterLease            DO NOT ADD
MutablePlaneDescriptor                   DO NOT ADD

PlaneDescriptor                          KEEP UNCHANGED
RasterLease                              KEEP AS LIFETIME CAPABILITY

resource access default                  READ ONLY
malloc-owned resource                    READ WRITE

read view from readOnly resource         ALLOW
read view from readWrite resource        ALLOW

writable view                            REQUIRE CERTIFICATION
writable implies uniqueness              NO
writable implies non-alias               NO

pairwise overlap checks                  KEEP OPERATION-LOCAL
```

This is the write-access provenance model for the next implementation phase.


#### E5.4c implementation boundary

E5.4c itself remains a design decision.

No production resource layout is changed in this step.

The next implementation work should establish the smallest internal
write-access representation and prove its propagation through:

```text
raw resource adoption
    ->
OwnedByteResource
    ->
ResourceEntry
    ->
RasterBacking
```

before introducing `WritableRasterView`.

This keeps capability provenance independently testable.

### E5.4c.1 retained write-access provenance

E5.4c.1 implements the storage-level provenance required before a retained
raster may later publish a writable semantic view.

The retained resource metadata now contains the package-internal capability:

```text
ResourceAccess
    readOnly
    readWrite
```

Its default state is deliberately conservative:

```text
ResourceAccess.init == ResourceAccess.readOnly
ResourceEntry.init.access == ResourceAccess.readOnly
```

Consequently, possession of a raw address, ownership of an allocation, or
successful backing validation does not by itself manufacture write access.

`tryAdoptMallocResource()` is the first production introduction boundary that
positively establishes `readWrite`.

That API is already an `@system` ownership boundary. Its contract now includes
the additional caller assertion that the complete adopted byte range is valid
writable storage. On successful adoption the resulting `OwnedByteResource`
therefore retains `ResourceAccess.readWrite`.

Package-internal raw adoption behaves differently:

```text
tryAdoptResourceEntryAssumeOwned()
    preserves ResourceEntry.access exactly
```

It does not infer write access from:

```text
void*
ownership
release policy
malloc compatibility
descriptor topology
backing reachability
```

This distinction is intentional. Source-specific adapters may establish their
own access provenance before raw adoption, but the generic ownership token does
not upgrade it.

The capability then survives the existing ownership pipeline as ordinary POD
metadata:

```text
ResourceEntry
    ->
OwnedByteResource
    ->
relinquishResource()
    ->
constructRetainedRaster()
    ->
copyMetadata!ResourceEntry
    ->
RasterBacking
```

No new ownership mechanism is required.

The general backing validator remains independent from access capability.
Validation proves address reachability and representation safety; it does not
prove mutability.

Temporary validation-only `ResourceEntry` values therefore remain
conservatively read-only without affecting validation behavior.

The implementation deliberately does not yet add:

```text
WritableRasterView
RasterLease.writeView()
mutable PlaneDescriptor
mutable sample-pointer formation
uniqueness
non-aliasing
restrict/noalias
public ResourceAccess
```

`ResourceAccess.readWrite` means only that mutation of the retained physical
resource has been positively permitted at its introduction boundary.

It does not mean that the resource is unique, exclusively borrowed, or
non-overlapping with another view.

E5.4c.1 therefore establishes the required storage provenance while leaving
the semantic writable-view and borrow model for the next stage.

### E5.4d semantic writable raster view

E5.4c and E5.4c.1 established retained per-resource write-access provenance.

E5.4d defines the semantic borrowing abstraction that may consume that
provenance.

The working type name is:

```text
WritableRasterView!T
```

The name is selected because the capability means exactly:

```text
samples represented by this view may be written
```

It deliberately does not imply:

```text
unique
exclusive
owned
non-aliasing
contiguous
single-plane
```

The type remains package-internal during its first implementation. Public
exposure is still deferred until the operation contracts have been reviewed.


#### Relationship to RasterView

`WritableRasterView!T` is the writable semantic peer of `RasterView!T`.

Both represent:

```text
non-owning raster borrow
logical plane order
Region2D resident geometry
descriptor-space coordinates
signed row stride
signed sample stride
multi-plane topology
empty regions
lifetime bounded by retained backing
```

They differ only in access capability:

```text
RasterView
    permits reads

WritableRasterView
    permits reads and writes
```

The writable type must not be derived merely by casting the pointer carried by
`PlaneDescriptor`.

Its existence certifies that the represented samples were proven writable.


#### Representation

The initial writable view should contain the same semantic geometry as
`RasterView`:

```text
const(PlaneDescriptor)[] planes
Region2D region
```

It does not need to retain `ResourceEntry[]` itself.

The proof chain is:

```text
RasterBacking
    resources + descriptors + region
              |
              | certification
              v
WritableRasterView
    descriptors + region
```

After successful certification, the writable-view type itself carries the
semantic capability.

The physical resources remain alive through the enclosing `RasterLease`
borrow.

This avoids coupling normal pixel traversal to retained resource metadata.


#### PlaneDescriptor remains unchanged

E5.4d preserves the existing decision:

```text
PlaneDescriptor.base == const(void)*
```

The descriptor remains access-neutral geometry.

A writable view therefore does not require:

```text
MutablePlaneDescriptor
void* PlaneDescriptor.base
duplicated mutable descriptor tables
```

Write permission comes from retained resource provenance plus certification,
not from the descriptor pointer qualifier.


#### Initial certification invariant

For every non-empty plane represented by a `WritableRasterView!T`:

```text
there exists at least one retained ResourceEntry
whose access is readWrite
and whose byte range contains every reachable T sample
of that plane for the represented Region2D
```

The proof must include the same geometry already required for read
reachability:

```text
descriptor-space x/y
signed row stride
signed sample stride
minimum reachable offset
maximum reachable offset
complete T sample width
address representability
```

Checking only the descriptor base address is insufficient.


#### Reuse existing reachability arithmetic

Writable certification must not implement a second independent physical
footprint algorithm.

The existing backing validator already establishes the relevant containment
relation for ordinary reachability.

The preferred implementation direction is therefore:

```text
existing shared containment arithmetic
        |
        +-- ordinary retained-backing validation
        |
        `-- writable certification with
            ResourceAccess.readWrite filtering
```

If required, the smallest existing private helper should be promoted to an
appropriate package-internal validation primitive.

This promotion must not expose raw resource metadata publicly.


#### One-resource containment remains the invariant

As with ordinary backing validation, one non-empty represented plane region
must be completely contained by one suitable retained resource.

Writable certification must not combine partial byte coverage from several
resources.

Thus:

```text
resource A covers first half
resource B covers second half
```

does not certify one plane region.

A storage model that genuinely spans resources requires a different raster
representation.


#### Mixed-access backing

A retained backing may contain:

```text
readOnly resources
readWrite resources
```

The initial whole-view certification succeeds only when every non-empty plane
represented by the resulting `WritableRasterView` is covered by a readWrite
resource.

Therefore:

```text
one non-writable represented plane
    ->
whole WritableRasterView certification fails
```

The backing itself remains valid and can still issue a normal `RasterView`.


#### Initial scope: complete plane set

The first writable view represents the same logical plane set as the retained
raster.

E5.4d does not yet introduce:

```text
writable plane-selection API
arbitrary writable band subsets
mixed read/write planes inside one WritableRasterView
```

The initial invariant is deliberately stronger:

```text
every plane represented by WritableRasterView is writable
```

A later selected-plane capability can be added without weakening this
invariant.


#### Empty semantics

An empty `Region2D` reaches no samples.

Therefore an empty writable view requires no writable physical sample range.

Conceptually:

```text
empty region
    ->
write certification succeeds without ResourceAccess.readWrite coverage
```

No mutable pixel pointer may be formed for an empty view.

Plane topology and lifetime semantics remain preserved.


#### Lifetime

`WritableRasterView` is non-owning.

When produced from `RasterLease`, it must be lifetime-bound to that lease in
the same manner as the existing read-only view:

```text
RasterLease
    |
    +-- view()
    |      ->
    |   RasterView
    |
    `-- tryWritableView(...)
           ->
        WritableRasterView
```

A writable view must not:

```text
outlive its RasterLease
escape into global storage from a local lease
return a child ROI whose parent borrow has expired
```

The existing DIP1000 strategy remains the model.


#### RasterLease remains a lifetime capability

`RasterLease` itself does not become synonymous with writable storage.

The same type may retain:

```text
fully read-only backing
fully read-write backing
mixed-access backing
```

Therefore the eventual lease API must express certification failure.

The preferred semantic shape is a fallible operation conceptually equivalent
to:

```text
lease.tryWritableView(...)
```

rather than:

```text
lease.writeView()
```

The exact production signature is deferred until the DIP1000 implementation is
tested.


#### No WritableRasterLease

E5.4d preserves the previous decision not to introduce a separate retained
ownership type merely for mutation.

Write capability belongs to the borrowed raster view, while `RasterLease`
continues to represent retained lifetime.

This keeps:

```text
ownership/lifetime
```

separate from:

```text
read/write access capability
```


#### Writable does not imply uniqueness

`WritableRasterView` may be copied within its permitted lifetime.

Multiple leases may retain the same backing.

Read-only and writable views may therefore alias physically.

This is deliberate.

The capability guarantees:

```text
writes are permitted
```

It does not guarantee:

```text
only this view may write
only this view may read
another plane cannot overlap
another raster cannot overlap
another lease cannot reference the storage
```

No `restrict`, LLVM `noalias`, unique-owner, or exclusive-borrow property may
be derived from the writable-view type.


#### Threading is a separate contract

Writable permission alone does not make concurrent mutation race-free.

E5.4d introduces no automatic synchronization and no thread-exclusive borrow.

Concurrent access policy belongs to a later execution/scheduling layer.

A future parallel kernel must establish whatever additional synchronization or
non-aliasing properties its execution semantics require.


#### ROI inheritance

A geometrically valid child ROI of an already-certified writable view remains
writable.

The reason is monotonic:

```text
child reachable sample set
    is a subset of
parent reachable sample set
```

Therefore writable resource certification need not be repeated for every ROI.

The writable ROI operation should mirror the geometry semantics of
`RasterView.tryRoi`.

However, it must not recover mutable access from a const-qualified writable
view.

The initial writable ROI API should therefore require a mutable receiver.


#### Read access through a writable view

A writable view may safely provide ordinary value reads.

Its read semantics should match `RasterView.trySample`.

This does not require creating a second physical capability.

A future convenience conversion:

```text
WritableRasterView
    ->
RasterView
```

is semantically valid because write capability strictly subsumes read
capability.

Such a conversion must remain lifetime-bound to the writable view or the same
retained backing.

E5.4d does not require this conversion for the first implementation.


#### Sample writes

The semantic control-plane write operation is conceptually:

```text
trySetSample(
    band,
    x,
    y,
    value
)
```

with coordinates relative to the writable view, matching
`RasterView.trySample`.

It must:

```text
reject invalid band
reject invalid x/y
perform no write on failure
support signed physical strides
support multi-plane descriptors
write exactly one T sample on success
```

It is a correctness/control-plane accessor, not the intended hot-loop kernel
interface.


#### Mutable pointer formation

The stored descriptor remains access-neutral and therefore exposes
`const(void)*`.

After writable certification, execution code eventually needs `T*`.

That conversion must occur only through a narrow trusted boundary associated
with the certified writable-view type.

Conceptually:

```text
certified WritableRasterView
        |
        | narrow @trusted pointer formation
        v
T*
```

The cast does not establish writability.

It consumes writability that has already been established by certification.


#### Execution bridge

The writable semantic type should eventually expose package-internal
capability queries analogous to the read view:

```text
plane execution traits
signed row/sample strides
mutable region-origin execution pointer
```

Those remain internal execution machinery.

The public semantic type must not expose:

```text
Mir slices
Canonical / Contiguous / Universal
raw ResourceEntry
ResourceAccess
physical-range proof machinery
```

E5.4e remains responsible for deriving specialized writable execution
capabilities such as `RasterTargetPlane`.


#### RasterTargetPlane remains downstream

`RasterTargetPlane!T` remains an execution specialization.

The intended layering is:

```text
WritableRasterView
    |
    | derive capability when layout permits
    v
RasterTargetPlane
    |
    v
Mir writable target / scalar kernel / specialized kernel
```

The direction must never be reversed.

A semantic writable raster is not defined by being contiguous.


#### Certification failure is semantic access failure

Failure to create a writable view because a represented plane lacks
write-capable retained storage is an access-capability result.

It is not:

```text
unsupportedExecution
```

and must not depend on Mir or layout specialization.

The first package-internal certification result may report at least:

```text
success
plane not writable
failing plane index
```

The exact eventual public error vocabulary is deferred to E5.4f.


#### No operation-specific alias proof is stored

Writable certification does not establish source/target relations.

In particular it must not store or cache:

```text
non-overlap with a RasterView
non-overlap with another WritableRasterView
same backing identity
memcpy eligibility
```

Those remain invocation-local operation facts.


#### Construction boundary

No general raw constructor should allow package users to manufacture a
writable view merely from:

```text
PlaneDescriptor[]
Region2D
```

The preferred construction boundary combines:

```text
retained ResourceEntry[]
stable PlaneDescriptor[]
Region2D
```

performs writable certification, and only then constructs the semantic type.

Child ROI construction is different: once the parent writable view has been
certified, a contained child may inherit the capability without consulting
resources again.


#### Initial visibility

The first implementation remains:

```text
package(imagery.raster)
```

even though the semantic type is designed as a future public abstraction.

This permits:

```text
DIP1000 testing
certification testing
mixed-access testing
signed-stride testing
operation integration
```

before the name and exact public constructors become compatibility promises.


#### E5.4d decisions

Current evidence supports:

```text
semantic type name                    WritableRasterView

initial visibility                    PACKAGE INTERNAL

representation                        PlaneDescriptor[] + Region2D
store ResourceEntry[] in view         NO
MutablePlaneDescriptor                NO

whole-view first                      YES
all represented planes writable       REQUIRED
selected writable band subsets        DEFER

empty view without writable bytes     ALLOW

lifetime model                        MIRROR RasterView
writable ROI                          INHERITS CERTIFICATION
const parent -> writable child         NO

control-plane sample read             ALLOW
control-plane sample write            ALLOW

writable means unique                 NO
writable means noalias                NO
writable means thread exclusive       NO

general raw writable constructor      DO NOT ADD

mutable pointer formation             NARROW @trusted
execution layouts                     KEEP INTERNAL
RasterTargetPlane                     KEEP DOWNSTREAM
```

This is the semantic contract for the first writable raster view.


#### E5.4d implementation boundary

The implementation should be split so that certification and view behavior can
be tested independently.

The next production stage should establish:

```text
E5.4d.1

1. shared writable containment certification
2. package-internal WritableRasterView!T
3. whole-backing certification
4. lease-bound writable borrow
5. writable ROI lifetime
6. trySample / trySetSample correctness
7. empty-region behavior
8. signed-stride behavior
9. mixed readOnly/readWrite rejection
10. DMD + LDC compile-negative lifetime tests
```

It should still not:

```text
export WritableRasterView publicly
adapt operations to it
derive RasterTargetPlane from it
define public copy/conversion APIs
```

Those remain subsequent E5.4 stages.


#### E5.4d.1 implementation checkpoint — 2026-09-19

All three semantic/lifetime implementation slices are now complete.

`E5.4d.1a` added package-internal writable-backing certification. Ordinary
backing validation remains the physical safety proof; writable certification
adds the requirement that every represented non-empty plane be completely
covered by at least one retained `ResourceAccess.readWrite` resource.

`E5.4d.1b` added package-internal `WritableRasterView!T` with:

```text
planeCount / region / width / height / empty
tryRoi
trySample
trySetSample
```

The raw assume-certified constructor is module-private. The package-visible
initial construction path requires retained resources, descriptors and region,
performs ordinary backing validation, performs writable certification, and only
then constructs the semantic writable capability.

The writable view stores descriptors plus region, not retained resource
metadata. It does not imply uniqueness, noalias, contiguity or thread
exclusivity.

DIP1000 compile probes with DMD and LDC verify:

```text
local writable use                     accepted
writable ROI read/write                accepted
return of scope-borrowed writable view rejected
global escape                          rejected
const parent -> writable child         rejected
raw assume-certified constructor use   rejected outside its module
external writable-view surface         rejected
```

`E5.4d.1c` adds the lease-bound writable borrow.

The implemented topology is:

```text
mutable RasterLease
        |
        | package-internal tryWritableView(...)
        v
SafeRefCounted.borrow
        |
        v
retained RasterBacking
        |
        v
ordinary backing validation
        |
        v
writable resource certification
        |
        v
WritableRasterView
```

The existing complete writable-view factory is deliberately reused even though
the retained backing was already validated before entering `RasterLease`.
This repeats ordinary validation on writable-borrow creation, but avoids adding
a second assume-validated capability-construction boundary before performance
evidence justifies one.

DMD and LDC compile probes establish that:

```text
mutable lease -> local writable borrow          accepted
caller-owned lease -> propagated writable borrow accepted
local lease -> returned writable view           rejected
local lease -> global writable view             rejected
const lease -> writable borrow                  rejected
const SafeRefCounted -> mutable payload borrow  rejected
```

The real `WritableRasterView` surface is usable through a `scope` borrow,
including:

```text
planeCount / region / width / height / empty
trySample
trySetSample
tryRoi
```

A read-only backing remains valid for `RasterView` but fails writable
certification. A retained backing whose resources carry `readWrite` provenance
may publish the writable semantic capability.

`RasterLease.init` also fails the writable-borrow operation safely without
entering an uninitialized `SafeRefCounted` payload.

No writable execution bridge or public raster operation API is introduced by
E5.4d.1a/b/c.

### E5.4 progression

The next steps are:

```text
E5.4a
    audit current public surface
    -> complete

E5.4b
    audit writable-raster prerequisites
    -> complete

E5.4c
    define retained write-access provenance
    -> complete: per-resource capability selected

E5.4c.1
    implement internal resource access provenance
    and verify transactional propagation
    -> complete

E5.4d
    define semantic writable raster view
    -> design complete

E5.4d.1
    implement and verify package-internal WritableRasterView
    -> complete

    E5.4d.1a
        writable backing certification
        -> complete

    E5.4d.1b
        semantic WritableRasterView
        writable ROI
        trySample / trySetSample
        signed-stride and empty-region behavior
        DMD + LDC lifetime probes
        -> complete

    E5.4d.1c
        lease-bound writable borrow
        RasterLease -> WritableRasterView
        const-lease exclusion
        DIP1000 escape protection
        -> complete

E5.4e
    derive internal writable execution capabilities from that view
    -> in progress

#### E5.4e.0 writable execution consumer audit — 2026-09-19

E5.4d established the semantic writable capability and its retained lifetime.
E5.4e now asks which execution capabilities are justified by existing
consumers.

The current writable execution consumers are:

```text
checked same-type copy
    RasterView source
        ->
    RasterTargetPlane target

exact ubyte -> float conversion
    RasterView!ubyte source
        ->
    RasterTargetPlane!float target
```

Both operations currently require the target to be:

```text
single logical plane
contiguous 2D
linear contiguous 1D
```

The existing Mir writable adapters likewise expose only:

```text
contiguous 2D target
flat contiguous 1D target
```

There is currently no production consumer requiring a writable:

```text
Universal 2D target
Canonical padded target
negative-stride target adapter
general affine writable Mir slice
```

E5.4e must therefore not create those capabilities speculatively.

The first execution bridge should derive the already-existing
`RasterTargetPlane!T` capability from a certified `WritableRasterView!T` only
when the represented plane satisfies the existing flat-contiguous execution
requirements.

The intended layering is:

```text
WritableRasterView
        |
        | package-internal execution metadata
        v
PlaneExecutionTraits
        |
        | require linearContiguous1D
        | for non-empty storage
        v
mutable region-origin execution pointer
        |
        | narrow trusted pointer/slice formation
        v
RasterTargetPlane
        |
        +-- existing Mir target adapters
        +-- checked copy
        `-- exact ubyte -> float conversion
```

`RasterTargetPlane` remains downstream execution machinery.

The dependency direction must therefore remain:

```text
internal target layer
    imports / consumes
WritableRasterView
```

and not:

```text
WritableRasterView
    depends on
RasterTargetPlane
```

The semantic writable view must remain independent of Mir and concrete target
representations.

The minimum `WritableRasterView` execution surface justified by the current
consumer is:

```text
tryPlaneExecutionTraits(...)
mutable executionRegionBase(...)
```

The first query exposes only derived layout metadata.

The second is the narrow package-internal mutable pointer boundary consuming
the writability already established by E5.4d certification.

No writable equivalent of:

```text
tryExecutionPlaneStrides(...)
```

is required yet because no current writable consumer needs explicit arbitrary
strides.

It should be added only when a concrete Canonical or Universal writable
execution consumer requires it.

Empty regions require special treatment consistent with the existing operation
model:

```text
valid plane + empty WritableRasterView
    ->
valid empty RasterTargetPlane
```

No mutable sample pointer is formed for the empty case and no flat-contiguous
sample capability is required because there are no reachable samples.

For a non-empty view, target derivation requires:

```text
valid plane index
linearContiguous1D == true
representable flatElementCount
mutable region-origin pointer
```

The existing backing validation has already established physical reachability.
Writable certification has already established write permission.

The target derivation must not infer:

```text
unique ownership
exclusive borrow
noalias
source/target non-overlap
thread exclusivity
```

Those remain separate operation-local facts.

The initial E5.4e implementation should therefore be split into:

```text
E5.4e.1
    add only the writable execution metadata/base primitives required by the
    contiguous target consumer
    -> complete

E5.4e.2
    derive RasterTargetPlane from WritableRasterView for valid contiguous
    planes, including empty-view semantics and DIP1000 lifetime tests
    -> complete

E5.4e.3
    verify existing copy/conversion consumers can use the derived target
    without exposing WritableRasterView, RasterTargetPlane, Mir, or execution
    layouts publicly
    -> complete
```

No broader writable execution abstraction is justified by current evidence.


#### E5.4e.1 writable execution primitives checkpoint — 2026-09-19

The first writable execution slice is now implemented.

`WritableRasterView!T` exposes exactly two new package-internal execution
primitives:

```text
tryPlaneExecutionTraits(...)
executionRegionBase(...)
```

`tryPlaneExecutionTraits` reuses the existing shared
`classifyPlaneExecutionLayout` implementation already used by `RasterView`.

No writable-specific layout classifier is introduced.

The resulting behavior remains:

```text
arbitrary affine / negative sample stride
    -> Universal

forward unit sample stride with padded rows
    -> Canonical

fully packed current region
    -> Contiguous + linearContiguous1D
```

Empty regions remain:

```text
Universal
linearContiguous1D = false
flatElementCount = 0
```

because they contain no reachable sample sequence requiring a physical
execution representation.

`executionRegionBase` is a narrow package-internal trusted boundary that forms
a mutable `T*` only from an already-certified `WritableRasterView`.

Its proof chain is:

```text
ordinary backing validation
        +
retained readWrite provenance
        +
writable backing certification
        +
WritableRasterView
        |
        v
mutable region-origin execution pointer
```

The function does not establish:

```text
unique ownership
exclusive borrowing
noalias
source/target non-overlap
thread exclusivity
```

Those properties remain outside the writable-view capability.

The pointer is lifetime-bound to the writable-view borrow.

DIP1000 compile probes with both DMD and LDC establish:

```text
const WritableRasterView -> execution traits
    accepted

mutable scope WritableRasterView -> local mutable execution base
    accepted

const WritableRasterView -> mutable execution base
    rejected

scope WritableRasterView -> returned mutable execution base
    rejected

scope WritableRasterView -> global mutable execution base
    rejected
```

Runtime tests additionally verify:

```text
Contiguous classification
Canonical padded classification
Universal negative-stride classification
empty-region null execution base
invalid-plane trait reset
ROI-origin pointer resolution
```

DMD and LDC unittests pass, the LDC release build passes, and all existing
compile-negative raster lifetime suites continue to pass under both compilers.

The writable-view trust budget now contains three distinct boundaries:

```text
makeWritableRasterViewAssumeCertified
    semantic writable-capability construction

trySetSample
    checked individual sample mutation

executionRegionBase
    mutable execution-pointer formation
```

No writable stride-query API, Mir writable adapter, new writable layout type,
or `RasterTargetPlane` dependency is added to `WritableRasterView`.

The dependency direction therefore remains ready for E5.4e.2:

```text
WritableRasterView
        |
        v
internal target derivation
        |
        v
RasterTargetPlane
```

#### E5.4e.2 contiguous writable target checkpoint — 2026-09-19

The first semantic-writable-view to execution-target bridge is now
implemented.

The dependency remains:

```text
WritableRasterView
        |
        | package-internal capability derivation
        v
RasterTargetPlane
```

and not the reverse.

`WritableRasterView` therefore remains independent of:

```text
RasterTargetPlane
Mir
operation-specific target types
```

The bridge is defined in the existing internal target layer and consumes:

```text
WritableRasterView
PlaneExecutionTraits
mutable region-origin execution pointer
```

For a non-empty plane derivation requires:

```text
valid logical plane index
linearContiguous1D == true
representable flatElementCount
certified mutable execution base
```

Canonical padded and Universal / negative-stride planes are deliberately
rejected.

No Canonical or Universal writable target type is introduced because no
current production consumer requires one.

Empty regions remain a semantic special case:

```text
valid empty writable plane
    ->
valid empty RasterTargetPlane

width / height
    preserved

elementCount
    0

executionBase
    null
```

No mutable execution pointer is formed for that case.

The bridge establishes no additional ownership or alias semantics.

In particular it does not imply:

```text
unique ownership
exclusive borrowing
noalias
source/target non-overlap
thread exclusivity
```

Those properties remain outside `RasterTargetPlane`, exactly as before.

A single new target-layer trusted boundary materializes D slice metadata from
an already-certified mutable execution pointer:

```text
T* + flatElementCount
        |
        | narrow @trusted
        v
T[]
        |
        v
existing RasterTargetPlane constructor
```

The higher-level `WritableRasterView -> RasterTargetPlane` bridge itself
remains `@safe`.

The existing target constructor is reused rather than duplicating its
dimension/count invariants.

##### DIP1000 provenance result

E5.4e.2 exposed an important D-specific lifetime detail.

The successful provenance chain is:

```text
return scope WritableRasterView
        |
        v
executionRegionBase
        |
        v
ordinary local auto pointer alias
        |
        v
ordinary local auto slice alias
        |
        v
RasterTargetPlane
        |
        v
optional Mir target
```

DMD and LDC preserve the originating `return scope` provenance through those
ordinary local aliases.

An earlier probe instead declared the intermediate aliases as:

```d
scope auto base
scope auto storage
```

and the positive return path was rejected with diagnostics equivalent to:

```text
returning scope variable storage is not allowed
```

Removing those local `scope` declarations produced the intended behavior.

This is a useful distinction:

```text
return scope
    describes provenance that may be returned with the originating borrow

local scope
    restricts the local alias itself from escaping its local lifetime
```

Adding `scope` to every intermediate alias is therefore not monotonically
"safer". In this case it unnecessarily shortened an already-correct lifetime
relationship.

The same result applies transitively through the existing Mir adapter.

Both DMD and LDC accept:

```text
caller return-scope WritableRasterView
    -> RasterTargetPlane
    -> return

caller return-scope WritableRasterView
    -> RasterTargetPlane
    -> Mir writable target
    -> return
```

Both reject:

```text
ordinary scope WritableRasterView
    -> returned RasterTargetPlane

ordinary scope WritableRasterView
    -> returned Mir target

ordinary scope WritableRasterView
    -> global RasterTargetPlane

const WritableRasterView
    -> mutable RasterTargetPlane
```

Runtime tests with both compilers verify:

```text
flat contiguous derivation and mutation
Canonical padded rejection
Universal / negative-stride rejection
empty target shape preservation
invalid plane rejection
one-row ROI becoming flat contiguous
correct ROI execution origin
```

The existing target representation, Mir target adapters and operation kernels
are unchanged, so no performance benchmark was required for E5.4e.2.

#### E5.4e.3 existing writable-consumer integration checkpoint — 2026-09-19

The existing writable execution consumers now have end-to-end regression
coverage through the retained writable path.

No new production dispatcher, operation wrapper, target representation or
writable execution abstraction was required.

The verified copy path is:

```text
OwnedByteResource
        |
        v
RasterLease!T
        |
        +----> RasterView!T source
        |
        `----> WritableRasterView!T
                    |
                    v
             RasterTargetPlane!T
                    |
                    v
      existing checked copy dispatcher
```

The verified conversion path is:

```text
OwnedByteResource
        |
        v
RasterLease!float
        |
        v
WritableRasterView!float
        |
        v
RasterTargetPlane!float
        |
        v
existing exact ubyte -> float conversion dispatcher
```

The dispatchers themselves remain unchanged.

They continue to accept:

```text
RasterView source
RasterTargetPlane target
```

rather than accepting `RasterLease`, `WritableRasterView`, Mir types or a new
operation-specific destination abstraction.

This keeps the layering:

```text
retained ownership / write provenance
        |
        v
semantic writable capability
        |
        v
contiguous execution target
        |
        v
operation-specific validation and dispatch
```

rather than folding ownership, write permission, layout capability and alias
relations into one type.


##### Alias semantics remain operation-local

The same retained backing may simultaneously provide:

```text
RasterView
WritableRasterView
RasterTargetPlane
```

within their valid borrow lifetimes.

That does not imply that a concrete operation may safely use those aliases
together.

An E5.4e.3 regression test deliberately derives:

```text
same RasterLease
        |
        +----> RasterView source
        |
        `----> WritableRasterView
                    |
                    v
             RasterTargetPlane target
```

and invokes the existing checked-copy dispatcher.

The target derivation succeeds because writable capability and contiguous
execution capability are valid.

The copy itself then returns:

```text
overlapDetected
```

before modifying storage.

This confirms that `WritableRasterView -> RasterTargetPlane` does not
manufacture:

```text
uniqueness
exclusivity
noalias
source/target non-overlap
thread exclusivity
```

Physical source/target non-overlap remains an invocation-local fact established
inside the operation that requires it.


##### Consumer audit result

The consumer audit found the checked copy and exact conversion dispatchers
already consume `RasterTargetPlane`.

No production call site required migration to a second target API.

The new retained writable path can therefore terminate at the established
target boundary:

```text
RasterLease
    -> WritableRasterView
    -> RasterTargetPlane
```

and reuse the existing operation implementations unchanged.

No speculative API was introduced for:

```text
copyToWritableView
convertToWritableView
NonOverlapToken
WritableCanonicalTarget
WritableUniversalTarget
```

The existing Canonical and Universal source execution machinery likewise does
not justify corresponding writable target types at this stage.


##### Verification

DMD and LDC both compile and pass retained end-to-end tests for:

```text
distinct retained source and destination -> checked copy success

same retained backing as source and destination
    -> target derivation succeeds
    -> checked copy reports overlapDetected
    -> storage remains unchanged

retained ubyte source + retained float destination
    -> writable target derivation succeeds
    -> exact conversion succeeds
    -> converted values are observable through the retained destination lease
```

The complete existing raster compile-negative suites continue to pass under
both DMD and LDC.

No benchmark rerun was required because E5.4e.3 changes only regression-test
coverage. Dispatcher implementations, target representation, Mir adapters and
hot kernels are unchanged.


#### E5.4e conclusion

E5.4e is complete.

The minimum writable execution chain justified by current consumers is now:

```text
RasterLease
        |
        v
WritableRasterView
        |
        | writable execution traits
        | mutable region-origin execution base
        v
RasterTargetPlane
        |
        +----> existing checked copy
        |
        `----> existing exact ubyte -> float conversion
```

No broader writable execution abstraction is currently evidence-backed.

The next stage is E5.4f.

E5.4f
    redesign public operation contracts independently of current dispatchers
    -> next

E5.4g
    expose only operation semantics supported by stable contracts
```

Reduction may ultimately be exposable earlier than source-to-target operations,
but E5.4a intentionally does not create a partial public operation namespace
before the overall semantic surface has been reviewed.

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

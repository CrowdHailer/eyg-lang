# Architectural Plan: Declarative Policy & WASM Execution in EYG

This document maps out the implementation plan for introducing native relational queries into EYG, compiling them to WebAssembly (WASM), and leveraging them as sandboxed access-control policies within the Open Policy Agent (OPA) ecosystem.

---

## 1. Adding Query Literals to EYG

EYG’s core AST is intentionally minimal to maximize predictability and portability. To add query capabilities without breaking its structural design, we will introduce a native **Datalog-style Query Literal block**.

### AST Extensions

We will add two new nodes to the EYG Intermediate Representation (IR):

* `Relation(name, row_type)`: Declares a collection schema.
* `Query([Clause])`: Evaluates a block of constraints.

### Syntax Design

Using EYG's existing brace-and-arrow conventions, a query block will bind logic variables to fields using a unification constraint syntax:

```eyg
# Define input schema using EYG's record structure
let allow = query {
  # Bind fields via pattern matching or equality
  input.user == "admin",
  input.action == "write",
}

```

### Type System Integration

EYG leverages **row polymorphism**. The query literals will use inference to reconstruct schemas dynamically. The type of a query that iterates over an input configuration will be inferred based on the fields accessed:

$$\tau = \text{Query}(\{ \text{user}: \text{String}, \text{action}: \text{String} \mid \rho \}) \to \text{Bool}$$

Where $\rho$ is the open row variable indicating that additional payload parameters can exist in the input safely.

---

## 2. Expressive Power: EYG Queries vs. Rego

To prove that EYG query literals can fully represent the expressive power of Rego, we map Rego’s key behaviors onto EYG’s functional/relational hybrid environment:

### Core Mappings

| Feature | Rego | EYG Query Equivalent |
| --- | --- | --- |
| **Logical AND** | Multiple expressions inside a block. | Comma-separated relational clauses. |
| **Logical OR** | Multiple rule blocks with the same name. | Sum types (Unions) or function composition. |
| **Iteration** | Implicit array expansion (`some x in array`). | Functional breakdown via pattern matching over lists. |

### Comparative Logic Snippet

#### Rego Source:

```rego
allow {
    input.user.role == "admin"
    input.action == "delete"
}

```

#### EYG Query Literal Equivalent:

```eyg
let allow = query {
  input.user.role == "admin",
  input.action == "delete",
}

```

---

## 3. Controlling Effects via Policy Enforcement

EYG relies heavily on **Managed Effects**. By default, applications have zero ambient authority; side effects must be declared and handled explicitly. We will implement a policy wrapper that intercepts and filters these effects before reaching the execution environment.

```
+------------------+                   +----------------------+
|  EYG Expression  | --(perform FX)--> | Effect Policy Engine |
+------------------+                   +----------------------+
                                                  |
                                           [Evaluates Query]
                                                  |
                                                  v
+------------------+                   +----------------------+
| Runtime Boundary | <---(Execute)---- |     Permitted?       |
+------------------+                   +----------------------+

```

### The Mechanism

1. When an EYG program triggers an effect (`perform HTTPGet(url)`), the runtime shifts control up to the handler layer.
2. The current context (environment variables, system clock, payload parameters) is structured into a record.
3. This record is evaluated against the `query` logic. If the query returns `False`, the effect is blocked, and an `AccessDenied` error is thrown directly into the code’s error recovery pathway.

---

## 4. The EYG-to-WASM Compiler Pipeline

To allow these policies to execute inside lightning-fast, sandboxed host systems, we will implement a direct pipeline targeting WebAssembly (`wasm32-unknown-unknown`).

```
  +--------------+          +-------------------+          +---------------+
  |    EYG IR    |  =====>  |  Linear Memory    |  =====>  |   WASM Binary |
  | (S-Expr AST) |          |  Layout Manager   |          |  (Wat/Binary) |
  +--------------+          +-------------------+          +---------------+

```

### Compilation Strategy

* **Memory Architecture:** Because EYG rules are non-mutating and short-lived during an auth check, we will utilize a simple **Linear Arena Allocator**. Memory resets completely at the end of each validation run, avoiding heavy garbage-collection overhead.
* **Relational Logic to Loops:** The compiler will unroll the declarative `query` statements into nested structural loops, checking bounds and records linearly.
* **ABI Export:** The compiler exports two foundational functions required by standard WASM embedding hosts:
* `alloc(size)`: Returns a pointer to provision incoming JSON contexts.
* `evaluate()`: Executes the binary block and outputs a single 1 or 0 byte result.



---

## 5. Running EYG Rules on OPA via WASM

Open Policy Agent (OPA) natively supports executing pre-compiled WASM modules instead of parsing raw Rego strings. This is where our pipeline connects directly into enterprise cloud infrastructure.

1. **Write the Policy in EYG:** policy.eyg.
Define the validation rule inside your EYG file leveraging structural logic matching.


2. **Compile to WebAssembly:** EYG Compiler Tooling.
Compile your policy file directly into an optimized WASM bytecode binary:

```bash
eyg compile --target=wasm policy.eyg -o policy.wasm

```


3. **Bundle the Artifact:** OPA CLI Setup.
Wrap the compiled `.wasm` file along with OPA’s required schema metadata descriptor (`data.json`) into a cohesive policy bundle tarball.


4. **Execute on the OPA Host:** WASM Runtime Execution.
Initialize OPA pointing directly to your new engine asset:

```bash
opa run --bundle policy.tar.gz

```

OPA maps incoming authorization queries directly to your compiled EYG instructions inside the WASM sandbox.


---

To watch Peter Saxton explain how the fundamental architecture of EYG tracks and structures these internal variables, check out this video outlining [Predictable and Useful Programming in EYG](https://www.youtube.com/watch?v=bzUXK5VBbXc). This design forms the baseline predictability that makes compiling policies into fast, reliable WASM modules achievable.
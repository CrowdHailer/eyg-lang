// alg W + Fix still here
// Row as in Fshrp guys 
// Split Row from to add union and Record
// Fsharp impl doesn't have separation between type var and row var so improper records

// Do it here with effects

// Need Free type var kind Eff
// Add Fix point to Effs
// walk through and hash types
// do/impl perform/handle key words better with label in primitives
// Hole and provider
import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/set
import gleam/javascript

fn set_singleton(k) {
  set.new()
  |> set.insert(k)
}

type Primitive {
  Int
  Binary
  RecordEmpty
  RecordSelect(label: String)
  // RecordExtend(label: String)
  // RecordRestrict(label: String)
  RecordUpdate(label: String)
  VariantCreate(label: String)
  VariantMatch(label: String)
  Perform(label: String)
  // First class cases
  Handle(label: String)
}

// in expression
// {l:M,.., Option(var)}
// case Option(var)
// Row Tail(Open | Closed) Extend
// always open or close i.e. in koka effects

type Expression {
  Variable(name: String)
  Primitive(primitive: Primitive)
  Lambda(name: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(name: String, definition: Expression, body: Expression)
}

// Fix(exp: Expression)
// LetRec(name: String, definition: Expression, body: Expression)

type Row(kind) {
  RowClosed
  RowOpen(Int)
  // Needs to be type for Type variable -> PR to kind in f-sharp code
  RowExtend(label: String, value: kind, tail: Row(kind))
}

type Type {
  TypeVariable(Int)
  TInt
  TBinary
  TFun(Type, Row(#(Type, Type)), Type)
  // Row parameterised by T for effects
  TUnion(Row(Type))
  TRecord(Row(Type))
}

type KindVar {
  TermVar(Int)
  RowVar(Int)
}

type Substitutions {
  // TODO this needs annother effects lookup
  Substitutions(
    terms: Map(Int, Type),
    rows: Map(Int, Row(Type)),
    effs: Map(Int, Row(#(Type, Type))),
  )
}

// TYPE
fn ftv(typ) {
  case typ {
    // TODO union type variables
    TFun(from, effects, to) -> set.union(ftv(from), ftv(to))
    TypeVariable(x) -> set_singleton(TermVar(x))
    TInt | TBinary -> set.new()
    TRecord(row) -> ftv_row(row)
    TUnion(row) -> ftv_row(row)
  }
}

// Top level
fn ftv_row(row) {
  case row {
    RowClosed -> set.new()
    RowOpen(x) -> set_singleton(RowVar(x))
    RowExtend(_label, value, tail) -> set.union(ftv(value), ftv_row(tail))
  }
}

fn apply(sub: Substitutions, typ) {
  case typ {
    TypeVariable(x) ->
      case map.get(sub.terms, x) {
        Ok(replace) -> replace
        Error(Nil) -> typ
      }
    TFun(from, effects, to) ->
      TFun(apply(sub, from), apply_effects(sub, effects), apply(sub, to))
    TInt | TBinary -> typ
    TRecord(row) -> TRecord(apply_row(sub, row, apply))
    TUnion(row) -> TUnion(apply_row(sub, row, apply))
  }
}

fn apply_row(sub: Substitutions, row, apply) {
  case row {
    RowClosed -> RowClosed
    RowOpen(x) ->
      case map.get(sub.rows, x) {
        Ok(replace) -> replace
        Error(Nil) -> row
      }
    RowExtend(label, value, tail) ->
      RowExtend(label, apply(sub, value), apply_row(sub, tail, apply))
  }
}

fn apply_effects(sub: Substitutions, effect) {
  case effect {
    RowClosed -> RowClosed
    RowOpen(x) ->
      case map.get(sub.effs, x) {
        Ok(replace) -> replace
        Error(Nil) -> effect
      }
    RowExtend(label, #(in, out), tail) ->
      RowExtend(
        label,
        #(apply(sub, in), apply(sub, out)),
        apply_effects(sub, tail),
      )
  }
  // RowExtend(label, apply(sub, value), apply_row(sub, tail, apply))
}

// Mu variables etc
type Scheme {
  Scheme(forall: List(KindVar), type_: Type)
}

fn set_drop(set, nope) {
  list.fold(nope, set, set.delete)
}

// scheme
fn ftv_scheme(scheme) {
  let Scheme(forall, typ) = scheme
  set_drop(ftv(typ), forall)
}

fn drop(sub: Substitutions, vars) {
  list.fold(
    vars,
    sub,
    fn(sub, var) {
      let Substitutions(terms, rows, effs) = sub
      case var {
        TermVar(x) -> Substitutions(map.drop(terms, [x]), rows, effs)
        RowVar(x) -> Substitutions(terms, map.drop(rows, [x]), effs)
      }
    },
  )
}

fn apply_scheme(sub, scheme) {
  let Scheme(forall, typ) = scheme
  Scheme(forall, apply(drop(sub, forall), typ))
}

type TypeEnv =
  Map(String, Scheme)

// TypeEnv
fn ftv_env(env: TypeEnv) {
  map.fold(
    env,
    set.new(),
    fn(state, _k, scheme) { set.union(state, ftv_scheme(scheme)) },
  )
}

fn apply_env(sub, env) {
  map.map_values(env, fn(_k, scheme) { apply_scheme(sub, scheme) })
}

// substitution map

fn compose(sub1: Substitutions, sub2: Substitutions) {
  let terms =
    map.merge(
      map.map_values(sub2.terms, fn(_k, v) { apply(sub1, v) }),
      sub1.terms,
    )
  let rows =
    map.merge(
      map.map_values(sub2.rows, fn(_k, v) { apply_row(sub1, v, apply) }),
      sub1.rows,
    )
  // TODO
  let effs = sub1.effs

  // map.merge(
  //   map.map_values(sub2.rows, fn(_k, v) { apply_row(sub1, v, apply) }),
  //   sub1.rows,
  // )
  Substitutions(terms, rows, effs)
}

// schema

fn generalize(env: Map(String, Scheme), typ) {
  let variables = set.to_list(set_drop(ftv_env(env), set.to_list(ftv(typ))))
  Scheme(variables, typ)
}

fn instantiate(scheme, ref) {
  let Scheme(vars, typ) = scheme
  let s =
    list.fold(
      vars,
      Substitutions(map.new(), map.new(), map.new()),
      fn(sub, v) {
        let Substitutions(terms, rows, effs) = sub
        case v {
          TermVar(x) ->
            Substitutions(
              map.insert(terms, x, TypeVariable(fresh(ref))),
              rows,
              effs,
            )
          RowVar(x) ->
            Substitutions(terms, map.insert(rows, x, RowOpen(fresh(ref))), effs)
        }
      },
    )

  apply(s, typ)
}

// typenv

// TODO example is missing RowOpen
fn rewrite_row(row, new_label, ref) {
  case row {
    RowClosed -> todo("row rewrite failed")
    RowExtend(label, field, tail) if label == new_label -> #(
      field,
      tail,
      map.new(),
    )
    RowOpen(old) -> todo
    RowExtend(label, field, tail) ->
      case tail {
        RowOpen(old) -> {
          let new = fresh(ref)
          let field = TypeVariable(fresh(ref))
          let subs =
            map.new()
            |> map.insert(old, RowExtend(new_label, field, RowOpen(new)))
          #(field, RowExtend(label, field, RowOpen(new)), subs)
        }
        row -> {
          let #(field1, tail1, subs) = rewrite_row(row, new_label, ref)
          #(field1, RowExtend(label, field, tail1), subs)
        }
      }
  }
  // _ -> todo("Not the right kind")
}

fn varbind(u, typ) {
  case typ {
    TypeVariable(x) if x == u -> Substitutions(map.new(), map.new(), map.new())
    _ ->
      case set.contains(ftv(typ), TermVar(u)) {
        True -> {
          map.new()
          todo("RECURSION IS BACK")
        }
        False -> {
          let terms =
            map.new()
            |> map.insert(u, typ)
          Substitutions(terms, map.new(), map.new())
        }
      }
  }
}

fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}

fn unify_effects(eff1, eff2) {
  case eff1, eff2 {
    RowClosed, RowClosed -> Substitutions(map.new(), map.new(), map.new())
    RowOpen(u), RowOpen(v) if u == v ->
      Substitutions(map.new(), map.new(), map.new())
    RowOpen(u), r | r, RowOpen(u) -> {
      let effs =
        map.new()
        |> map.insert(u, r)
      Substitutions(map.new(), map.new(), effs)
    }
  }
}

fn unify(t1, t2) {
  case t1, t2 {
    TFun(from1, effects1, to1), TFun(from2, effects2, to2) -> {
      let s1 = unify(from1, from2)
      let s2 = unify(apply(s1, to1), apply(s1, to2))
      // io.debug(effects1)
      // io.debug(effects2)
      let s3 = compose(s2, s1)
      // apply row pulls out of substitutions
      // apply_effects(s3, effects1, fn(s, r) { Nil })
      io.debug("unify effects")
      unify_effects(apply_effects(s3, effects1), apply_effects(s3, effects2))
      |> io.debug
    }
    TypeVariable(u), t | t, TypeVariable(u) -> varbind(u, t)
  }
  // | TInt, TInt -> Map.empty
  // | TBool, TBool -> Map.empty
  // | _ -> failwithf "Types do not unify: %A vs %A" t1 t2
}

fn infer_primitive(primitive, ref) {
  case primitive {
    Int -> TInt
    Binary -> TBinary
    RecordEmpty -> TRecord(RowClosed)
    // RecordExtend(label) -> {
    //   let a = fresh(ref)
    //   let r = fresh(ref)
    //   // Should this be record of type r
    //   TFun(a, TFun(r, TRecord(RowExtend(label, a, r))))
    // }
    RecordUpdate(label) -> {
      let new = TypeVariable(fresh(ref))
      let old = TypeVariable(fresh(ref))
      let r = fresh(ref)
      // Should this be record of type r
      TFun(
        new,
        RowOpen(fresh(ref)),
        TFun(
          TRecord(RowExtend(label, old, RowOpen(r))),
          RowOpen(fresh(ref)),
          TRecord(RowExtend(label, new, RowOpen(r))),
        ),
      )
    }
    RecordSelect(label) -> {
      let field = TypeVariable(fresh(ref))
      assert r = fresh(ref)
      TFun(
        TRecord(RowExtend(label, field, RowOpen(r))),
        RowOpen(fresh(ref)),
        field,
      )
    }
    VariantCreate(label) -> {
      let new = TypeVariable(fresh(ref))
      let row = RowOpen(fresh(ref))
      TFun(new, RowOpen(fresh(ref)), TUnion(RowExtend(label, new, row)))
    }
    VariantMatch(label) -> todo
    Perform(label) -> {
      let input = TypeVariable(fresh(ref))
      let output = TypeVariable(fresh(ref))
      let row = RowOpen(fresh(ref))
      let effect = RowExtend(label, #(input, output), row)
      TFun(input, effect, output)
    }
    Handle(label) -> todo
  }
  // _ -> todo
}

fn do_infer(env, exp, ref) {
  case exp {
    Variable(x) -> {
      assert Ok(scheme) = map.get(env, x)
      let typ = instantiate(scheme, ref)
      #(
        Substitutions(map.new(), map.new(), map.new()),
        typ,
        RowOpen(fresh(ref)),
      )
    }
    Primitive(primitive) -> #(
      Substitutions(map.new(), map.new(), map.new()),
      infer_primitive(primitive, ref),
      RowOpen(fresh(ref)),
    )
    Lambda(name, body) -> {
      let tparam = TypeVariable(fresh(ref))
      let env1 = map.insert(env, name, Scheme([], tparam))
      let #(s1, tbody, eff) = do_infer(env1, body, ref)
      // TODO this needs the perform combination
      // There a M vs W equivalence here
      #(
        s1,
        TFun(apply(s1, tparam), RowOpen(fresh(ref)), tbody),
        RowOpen(fresh(ref)),
      )
    }
    Apply(func, arg) -> {
      let eff = RowOpen(fresh(ref))
      let #(s1, tfunc, eff_f) = do_infer(env, func, ref)
      let #(s2, targ, eff_a) = do_infer(apply_env(s1, env), arg, ref)
      let treturn = TypeVariable(fresh(ref))
      // TODO unify matters for effects
      // Need to keep track of effects of program
      // io.debug(eff_f)
      // io.debug(eff_a)
      // io.debug(#(tfunc, "========="))
      let s3 = unify(apply(s2, tfunc), TFun(targ, eff, treturn))
      io.debug(#(s3, "-------------s3"))
      #(
        compose(compose(s3, s2), s1),
        apply(s3, treturn),
        apply_effects(s3, eff),
      )
    }
    // Close rows on Let and Lambda
    Let(name, def, body) -> {
      let #(s1, tvalue, eff) = do_infer(env, def, ref)
      let scheme = generalize(apply_env(s1, env), tvalue)
      let env = map.insert(env, name, scheme)
      let #(s2, tthen, eff) = do_infer(env, body, ref)
      #(compose(s2, s1), tthen, RowOpen(fresh(ref)))
    }
  }
  // Fix(expression) -> {
  //   let #(s1, tconstructor) = do_infer(env, expression, ref)
  //   let tfunc = fresh(ref)
  //   let s2 = unify(TFun(tfunc, tfunc), tconstructor)
  //   #(compose(s2, s1), tfunc)
  // }
  // LetRec(_, _, _) -> todo("letrec")
  // kind and row variable can be optional
}

fn infer_env(env, exp) {
  let #(s, typ, eff) = do_infer(env, exp, javascript.make_reference(0))
  // io.debug(s)
  // apply eff TODO
  #(apply(s, typ), eff)
}

fn infer(exp) {
  infer_env(map.new(), exp)
}

// W with effects

pub fn primitve_test() {
  assert #(TInt, RowOpen(_)) = infer(Primitive(Int))
  assert #(TBinary, RowOpen(_)) = infer(Primitive(Binary))

  // io.debug("----------------")
  // assert _ =
  //   infer(
  //     map.new(),
  //     Lambda(
  //       "x",
  //       Apply(
  //         Apply(Primitive(RecordUpdate("foo")), Primitive(Int)),
  //         Variable("x"),
  //       ),
  //     ),
  //   )
  // let select = fn(x, e) { Apply(Primitive(RecordSelect("foo")), e) }
  // io.debug("----------------!!!!!!!!!!!!!!!!!")
  // assert _ =
  //   infer(
  //     map.new(),
  //     Lambda(
  //       "x",
  //       Let(
  //         "_",
  //         select("foo", Variable("x")),
  //         Let("_", select("bar", Variable("x")), Primitive(Int)),
  //       ),
  //     ),
  //   )
  //   |> io.debug
  // todo("row test")
  // assert _ =
  //   infer(Apply(Primitive(Perform("foo")), Primitive(Binary)))
  //   |> io.debug
  Nil
}

pub fn assignment_test() {
  let source = Let("x", Primitive(Int), Variable("x"))
  assert #(TInt, RowOpen(_)) = infer(source)
  Nil
}

pub fn raise_effect_test() {
  let source = Apply(Primitive(Perform("foo")), Primitive(Int))
  assert #(TypeVariable(ret), eff) = infer(source)
  ret
  |> io.debug
  eff
  |> io.debug

  todo
}
// pub fn combined_effect_test() {
//   let source =
//     Let(
//       "_",
//       Apply(Primitive(Perform("foo")), Primitive(Int)),
//       Apply(Primitive(Perform("bar")), Primitive(Binary)),
//     )
//   assert #(TypeVariable(ret), eff) = infer(source)
//   ret
//   |> io.debug
//   eff
//   |> io.debug

//   todo
// }

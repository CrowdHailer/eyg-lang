import gleam/list
import gleam/map.{Map}
import gleam/javascript

type Primitive {
  Int
  Binary
}

type Expression {
  Variable(name: String)
  Primitive(primitive: Primitive)
  Lambda(name: String, body: Expression)
  Apply(func: Expression, argument: Expression)
  Let(name: String, definition: Expression, body: Expression)
  LetRec(name: String, definition: Expression, body: Expression)
}

// What happens with non recursive let Rec

type Type {
  TypeVariable(Int)
  TInt
  TBinary
  TFun(Type, Type)
}

type Scheme {
  Scheme(forall: List(Int), type_: Type)
}

type TypeEnv =
  Map(String, Scheme)

type Subst =
  Map(String, Type)

// TYPE
fn ftv(typ) {
  case typ {
    TFun(from, to) -> map.merge(ftv(from), ftv(to))
    TypeVariable(x) ->
      map.new()
      |> map.insert(x, [])
    TInt | TBinary -> map.new()
  }
}

fn apply(sub, typ) {
  case typ {
    TypeVariable(x) ->
      case map.get(sub, x) {
        Ok(replace) -> replace
        Error(Nil) -> typ
      }
    TFun(from, to) -> TFun(apply(sub, from), apply(sub, to))
    TInt | TBinary -> typ
  }
}

// scheme
fn ftv_scheme(scheme) {
  let Scheme(forall, typ) = scheme
  map.drop(ftv(typ), forall)
}

fn apply_scheme(sub, scheme) {
  let Scheme(forall, typ) = scheme
  Scheme(forall, apply(map.drop(sub, forall), typ))
}

// TypeEnv
fn ftv_env(env: TypeEnv) {
  map.fold(
    env,
    map.new(),
    fn(state, _k, scheme) { map.merge(state, ftv_scheme(scheme)) },
  )
}

fn apply_env(sub, env) {
  map.map_values(env, fn(_k, scheme) { apply_scheme(sub, scheme) })
}

// Substitutions

fn compose(sub1, sub2) {
  map.merge(map.map_values(sub2, fn(_k, v) { apply(sub1, v) }), sub1)
}

fn generalize(env: Map(String, Scheme), typ) {
  let variables = map.keys(map.drop(ftv_env(env), map.keys(ftv(typ))))
  Scheme(variables, typ)
}

fn instantiate(scheme, ref) {
  let Scheme(vars, typ) = scheme
  let s =
    list.map(vars, fn(v) { #(v, fresh(ref)) })
    |> map.from_list
  apply(s, typ)
}

// let instantiate (ts : Scheme) =
//     match ts with
//     | Scheme(vars, t) ->
//         let nvars = vars |> List.map (fun name -> newTyVar (string name.[0]) )
//         let s = List.zip vars nvars |> Map.ofList
//         Typ.apply s t

fn varbind(u, typ) {
  case typ {
    TypeVariable(x) if x == u -> map.new()
    _ ->
      case map.get(ftv(typ), u) {
        Ok(_) -> todo("RECURSION IS BACK")
        Error(Nil) ->
          map.new()
          |> map.insert(u, typ)
      }
  }
}

fn unify(t1, t2) {
  case t1, t2 {
    TFun(from1, to1), TFun(from2, to2) -> {
      let s1 = unify(from1, from2)
      let s2 = unify(apply(s1, to1), apply(s1, to2))
      compose(s2, s1)
    }
    TypeVariable(u), t | t, TypeVariable(u) -> varbind(u, t)
  }
  // | TInt, TInt -> Map.empty
  // | TBool, TBool -> Map.empty
  // | _ -> failwithf "Types do not unify: %A vs %A" t1 t2
}

fn infer_primitive(primitive) {
  case primitive {
    Int -> TInt
    Binary -> TBinary
  }
}

fn fresh(ref) {
  TypeVariable(javascript.update_reference(ref, fn(x) { x + 1 }))
}

// state could just be ref
fn do_infer(env, exp, ref) {
  case exp {
    Variable(x) -> {
      assert Ok(scheme) = map.get(env, x)
      let typ = instantiate(scheme, ref)
      #(map.new(), typ)
    }
    Primitive(primitive) -> #(map.new(), infer_primitive(primitive))
    Lambda(name, body) -> {
      let tparam = fresh(ref)
      let env1 = map.insert(env, name, Scheme([], tparam))
      let #(s1, tbody) = do_infer(env1, body, ref)
      #(s1, TFun(apply(s1, tparam), tbody))
    }
    Apply(func, arg) -> {
      let #(s1, tfunc) = do_infer(env, func, ref)
      let #(s2, targ) = do_infer(apply_env(s1, env), arg, ref)
      let treturn = fresh(ref)
      let s3 = unify(apply(s2, tfunc), TFun(targ, treturn))
      #(compose(compose(s3, s2), s1), apply(s3, treturn))
    }
    Let(name, def, body) -> {
      let #(s1, tvalue) = do_infer(env, def, ref)
      let scheme = generalize(apply_env(s1, env), tvalue)
      let env = map.insert(env, name, scheme)
      let #(s2, tthen) = do_infer(env, body, ref)
      #(compose(s2, s1), tthen)
    }
    LetRec(_, _, _) -> todo("letrec")
  }
}

fn infer(env, exp) {
  let #(s, typ) = do_infer(env, exp, javascript.make_reference(0))
  apply(s, typ)
}

pub fn function_name_test() {
  assert TBinary = infer(map.new(), Primitive(Binary))

  assert TBinary =
    infer(map.new(), Apply(Lambda("_", Primitive(Binary)), Primitive(Int)))

  assert TInt =
    infer(map.new(), Apply(Lambda("x", Variable("x")), Primitive(Int)))

  assert TInt = infer(map.new(), Let("x", Primitive(Int), Variable("x")))
  //   todo
  []
}

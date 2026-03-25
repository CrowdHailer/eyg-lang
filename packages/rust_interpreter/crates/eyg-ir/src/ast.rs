// IR AST type definitions
// Mirrors packages/gleam_ir/src/eyg/ir/tree.gleam

use serde::{Deserialize, Deserializer, Serialize};

/// A Node is an Expression paired with metadata.
/// For the initial port, metadata is fixed to () (unit type).
/// We use a newtype wrapper to allow custom Deserialize/Serialize implementations.
#[derive(Debug, Clone, PartialEq)]
pub struct Node(pub Expr, pub ());

/// Helper function to create a Node from an Expr
pub fn node(expr: Expr) -> Node {
    Node(expr, ())
}

/// Custom deserializer for Node that deserializes just the Expr
/// and pairs it with () metadata
impl<'de> Deserialize<'de> for Node {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let expr = Expr::deserialize(deserializer)?;
        Ok(Node(expr, ()))
    }
}

/// Custom serializer for Node
impl Serialize for Node {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        self.0.serialize(serializer)
    }
}

/// Expression represents all IR node types in the EYG language.
/// This mirrors the Expression(m) type from tree.gleam.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "0")]
pub enum Expr {
    /// Variable reference
    #[serde(rename = "v")]
    Variable {
        #[serde(rename = "l")]
        label: String,
    },

    /// Lambda abstraction (function)
    #[serde(rename = "f")]
    Lambda {
        #[serde(rename = "l")]
        label: String,
        #[serde(rename = "b")]
        body: Box<Node>,
    },

    /// Function application
    #[serde(rename = "a")]
    Apply {
        #[serde(rename = "f")]
        func: Box<Node>,
        #[serde(rename = "a")]
        argument: Box<Node>,
    },

    /// Let binding
    #[serde(rename = "l")]
    Let {
        #[serde(rename = "l")]
        label: String,
        #[serde(rename = "v")]
        definition: Box<Node>,
        #[serde(rename = "t")]
        body: Box<Node>,
    },

    /// Binary data (byte array)
    #[serde(rename = "x")]
    Binary {
        #[serde(rename = "v")]
        #[serde(deserialize_with = "crate::dag_json::deserialize_dag_binary")]
        #[serde(serialize_with = "crate::dag_json::serialize_dag_binary")]
        value: Vec<u8>,
    },

    /// Integer literal
    #[serde(rename = "i")]
    Integer {
        #[serde(rename = "v")]
        value: i64,
    },

    /// String literal
    #[serde(rename = "s")]
    String {
        #[serde(rename = "v")]
        value: String,
    },

    /// Empty list (tail)
    #[serde(rename = "ta")]
    Tail,

    /// List constructor
    #[serde(rename = "c")]
    Cons,

    /// Vacant (zero/bottom type)
    #[serde(rename = "z")]
    Vacant,

    /// Empty record (unit)
    #[serde(rename = "u")]
    Empty,

    /// Extend record with field
    #[serde(rename = "e")]
    Extend {
        #[serde(rename = "l")]
        label: String,
    },

    /// Select field from record
    #[serde(rename = "g")]
    Select {
        #[serde(rename = "l")]
        label: String,
    },

    /// Overwrite field in record
    #[serde(rename = "o")]
    Overwrite {
        #[serde(rename = "l")]
        label: String,
    },

    /// Tag a value (union constructor)
    #[serde(rename = "t")]
    Tag {
        #[serde(rename = "l")]
        label: String,
    },

    /// Case branch (pattern match on tag)
    #[serde(rename = "m")]
    Case {
        #[serde(rename = "l")]
        label: String,
    },

    /// No cases (empty pattern match)
    #[serde(rename = "n")]
    NoCases,

    /// Perform an effect
    #[serde(rename = "p")]
    Perform {
        #[serde(rename = "l")]
        label: String,
    },

    /// Handle an effect
    #[serde(rename = "h")]
    Handle {
        #[serde(rename = "l")]
        label: String,
    },

    /// Built-in function reference
    #[serde(rename = "b")]
    Builtin {
        #[serde(rename = "l")]
        identifier: String,
    },

    /// CID reference
    #[serde(rename = "#")]
    Reference {
        #[serde(rename = "l")]
        #[serde(deserialize_with = "crate::dag_json::deserialize_dag_cid")]
        #[serde(serialize_with = "crate::dag_json::serialize_dag_cid")]
        identifier: String,
    },

    /// Package release reference
    #[serde(rename = "@")]
    Release {
        #[serde(rename = "p")]
        package: String,
        #[serde(rename = "r")]
        release: i64,
        #[serde(rename = "l")]
        #[serde(deserialize_with = "crate::dag_json::deserialize_dag_cid")]
        #[serde(serialize_with = "crate::dag_json::serialize_dag_cid")]
        identifier: String,
    },
}


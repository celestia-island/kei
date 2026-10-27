//! Typed world-state store for physical-consistency entity tracking.
//!
//! Moved from plana (2026-10-27 user ruling: this is kei-domain vocabulary —
//! the physical-world state map belongs to the OS side, not the platform
//! layer). While `plana_sync` synchronises *UI* state (untyped JSON trees),
//! this crate tracks the *physical* world — typed entities with attributes,
//! data quality, and dual timestamps — so agents and world-model services
//! share one queryable "what is, right now".
//!
//! # Status: awaiting the kernel-interface study
//!
//! The former `ingest` seam (industrial-telemetry mapping onto entities)
//! did NOT move: it depended on plana's wire types, which kei must not
//! depend on. How device state is mapped here — directly from kernel-
//! exposed interfaces (the Linux/Bootloader-style vendor-kernel contract:
//! we call the vendor kernel's interfaces, we do not reach into its
//! internals) — is the open study; until it lands, this crate is a
//! self-contained store with no producer.
//!
//! # Design
//!
//! - [`WorldStateStore`] follows a single-writer + broadcast pattern,
//!   storing typed [`WorldEntity`] values.
//! - Entities carry a wall-clock timestamp (`updated_wall`, for display and
//!   audit) and an optional monotonic capture timestamp (`updated_mono_ns`,
//!   for ordering and sensor fusion).
//! - [`WorldEventLog`] is the append-only persistence seam; the store itself
//!   is in-memory only.
//!
//! # Semantics notes
//!
//! - **Steady-state liveness**: an upsert whose *attributes* are unchanged
//!   but whose `updated_wall` advanced still counts as a change — the wall
//!   timestamp is observable liveness ("alive, value unchanged" vs "no
//!   data"). Subscribers that only care about value changes must diff
//!   `attributes` themselves.
//! - **Broadcast**: the change channel is a `tokio::broadcast`; a subscriber
//!   that falls more than `capacity` changes behind receives `Lagged` and
//!   should re-read [`WorldStateStore::snapshot`]. Broadcast version
//!   ordering is only guaranteed for a single writer thread.
//! - **NaN**: `AttributeValue::Number(f64)` does not survive NaN (JSON has
//!   no NaN — it serialises to `null` and reads back as `Json(null)`);
//!   producers should map non-finite values to [`Quality::Error`] instead.

pub mod store;
pub mod types;

pub use store::{WorldChange, WorldStateStore};
pub use types::{AttributeValue, Quality, WorldEntity};

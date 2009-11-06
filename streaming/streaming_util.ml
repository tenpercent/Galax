(***********************************************************************)
(*                                                                     *)
(*                                 GALAX                               *)
(*                              XQuery Engine                          *)
(*                                                                     *)
(*  Copyright 2001-2007.                                               *)
(*  Distributed only by permission.                                    *)
(*                                                                     *)
(***********************************************************************)

(* $Id: streaming_util.ml,v 1.7 2007/02/01 22:08:54 simeon Exp $ *)

(* Module: Streaming_util
   Description:
     Some utilities over streaming types.
*)


open Error

open Namespace_names
open Namespace_symbols
open Namespace_resolve
open Namespace_context

open Datatypes
open Datatypes_util

open Streaming_types


(********************)
(* The empty stream *)
(********************)

let empty_xml_stream          () = Cursor.cursor_of_list []
let empty_resolved_xml_stream () = Cursor.cursor_of_list [] 
let empty_typed_xml_stream    () = Cursor.cursor_of_list []


let fmkse_event desc fi = 
  { se_desc = desc; 
    se_loc = fi }

let fmkrse_event desc fi = 
  { rse_desc = desc; 
    rse_loc = fi }

let fmktse_event desc fi =
  { tse_desc = desc;
    tse_annot = Sax_annot.empty_sax_annot();
    tse_loc = fi }

let fmkatse_event desc annot fi =
  { tse_desc = desc;
    tse_annot = annot;
    tse_loc = fi }

let fmkotse_event desc annot fi =
  { otse_desc = desc;
    otse_annot = annot;
    otse_loc = fi }

let mktse_event desc = fmktse_event desc Finfo.bogus


(*******************************)
(* Extracts special attributes *)
(*******************************)

(* Process an xmlns attribute *)

let build_uri att content_thing =
  try
    (* Hack for now! - Jerome *)
    ignore(anyURI_of_untyped content_thing);
    NSUri content_thing
  with
  | _ ->
      let ns_attribute = Namespace_names.string_of_uqname att in
      raise (Query (Mapping_Failure ("Namespace attribute " ^ ns_attribute ^ " does not contain a URI")))

let build_prefix_uri_pair att prefix_thing content_thing =
  let ns_prefix =
    match prefix_thing with
    | Some ncame ->
	NSPrefix ncame
    | None ->
	NSDefaultElementPrefix
  in
  let uri = build_uri att content_thing in
  (ns_prefix, uri)

(* This function extracts special attributes after parsing *)

let rec extract_special_attributes attributes =
  match attributes with
  | [] ->
    (Whitespace.Default, [], None, [])
  | att1 :: attributes' ->
      begin
	let (whitespace_mode, namespace_decls, base_uri, other_attributes') =
	  extract_special_attributes attributes'
	in
	match att1 with
	  (* Note: in the case of xmlns attributes, those do not get
	     preserved in the final Infoset.
	     - Jerome *)
	| ((NSPrefix "xmlns", ncname), att_content) ->
	    let new_namespace_decl =
	      build_prefix_uri_pair (fst att1) (Some ncname) att_content
	    in
	    (whitespace_mode, new_namespace_decl :: namespace_decls, base_uri, other_attributes')
	| ((NSDefaultElementPrefix, "xmlns"), att_content) ->
	    let new_namespace_decl =
	      build_prefix_uri_pair (fst att1) None att_content
	    in
	    (whitespace_mode, new_namespace_decl :: namespace_decls, base_uri, other_attributes')
	      (* Note:
		 Other special attributes are preserved in the XML
		 Infoset.
		 - Jerome *)
	| ((NSPrefix "xml", "space"), "preserve") ->
	    (Whitespace.Preserve, namespace_decls, base_uri, att1 :: other_attributes')
	| ((NSPrefix "xml", "space"), "default") ->
	    (Whitespace.Default, namespace_decls, base_uri, att1 :: other_attributes')
	| ((NSPrefix "xml", "base"), att_content) ->
	    let base_uri = AnyURI._kinda_uri_of_string att_content in
	    let base_uri_dm = new Dm_atomic.atomicAnyURI base_uri in
	    (whitespace_mode, namespace_decls, Some base_uri_dm, other_attributes')
           (* For normal attributes, just add them to the final list of attributes *)
	| _ ->
	    (whitespace_mode, namespace_decls, base_uri, att1 :: other_attributes')
      end


(* Checks for duplicates in attributes -- Returns the original
   sequence of attributes or raises and error *)

let local_attribute_hash = Hashtbl.create 17

let check_duplicate_attributes attributes =
  let _ = Hashtbl.clear local_attribute_hash in
  let add_function (asym,_) =
    let (_,uri,local) = asym in
    if (Hashtbl.mem local_attribute_hash (uri,local))
    then
      let caname = Namespace_symbols.rattr_name asym in
      let aname = Namespace_names.prefixed_string_of_rqname caname in
      raise (Query (Datamodel ("Attribute " ^ aname ^ " is duplicated in element")))
    else
      (Hashtbl.add local_attribute_hash (uri,local) ())
  in
  List.iter add_function attributes;
  attributes

let string_of_resolved_sax_event_desc rse = 
  match rse with
  | RSAX_startDocument _ -> "RSAX_startDocument"
  | RSAX_endDocument     -> "RSAX_endDocument"
  | RSAX_startElement  _ -> "RSAX_startElement"
  | RSAX_endElement      -> "RSAX_endElement"
  | RSAX_processingInstruction _ -> "RSAX_processingInstruction"
  | RSAX_comment       _ -> "RSAX_comment"
  | RSAX_characters    _ -> "RSAX_characters"
  | RSAX_attribute     _ -> "RSAX_attribute"
  | RSAX_atomicValue   _ -> "RSAX_atomicValue"
  | RSAX_hole            -> "RSAX_hole"

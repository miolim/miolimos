SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: knowledge_items_search_vector_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.knowledge_items_search_vector_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('german', coalesce(NEW.title, '')), 'A') ||
    setweight(to_tsvector('german', coalesce(array_to_string(NEW.aliases, ' '), '')), 'A') ||
    setweight(to_tsvector('german', coalesce(array_to_string(NEW.tags, ' '), '')), 'B') ||
    setweight(to_tsvector('german', coalesce(NEW.body, '')), 'C');
  RETURN NEW;
END;
$$;


--
-- Name: tasks_search_vector_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tasks_search_vector_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('german', coalesce(NEW.title, '')), 'A') ||
    setweight(to_tsvector('german', coalesce(NEW.description, '')), 'C');
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actor_mentions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actor_mentions (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    actor_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: actor_mentions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actor_mentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actor_mentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actor_mentions_id_seq OWNED BY public.actor_mentions.id;


--
-- Name: actor_views; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actor_views (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    viewable_type character varying NOT NULL,
    viewable_id character varying NOT NULL,
    viewed_at timestamp(6) without time zone NOT NULL,
    duration_ms integer DEFAULT 0 NOT NULL,
    was_edited boolean DEFAULT false NOT NULL,
    session_token character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: actor_views_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actor_views_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actor_views_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actor_views_id_seq OWNED BY public.actor_views.id;


--
-- Name: actors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actors (
    id bigint NOT NULL,
    type character varying NOT NULL,
    name character varying NOT NULL,
    email character varying,
    active boolean DEFAULT true NOT NULL,
    api_token character varying,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    password_digest character varying,
    last_seen_at timestamp(6) without time zone,
    inbox_run_requested_at timestamp(6) without time zone,
    workflow_instructions text,
    show_in_dashboard boolean DEFAULT true NOT NULL,
    preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
    signature_image text,
    role integer DEFAULT 1 NOT NULL,
    person_ki_uuid character varying
);


--
-- Name: actors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actors_id_seq OWNED BY public.actors.id;


--
-- Name: affiliations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.affiliations (
    id bigint NOT NULL,
    person_uuid character varying NOT NULL,
    organization_uuid character varying NOT NULL,
    role character varying DEFAULT ''::character varying NOT NULL,
    start_at date,
    end_at date,
    "primary" boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: affiliations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.affiliations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: affiliations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.affiliations_id_seq OWNED BY public.affiliations.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    action character varying NOT NULL,
    auditable_type character varying NOT NULL,
    auditable_id bigint NOT NULL,
    changes_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: awaiting_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.awaiting_topics (
    id bigint NOT NULL,
    awaiting_id bigint NOT NULL,
    topic_id bigint NOT NULL
);


--
-- Name: awaiting_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.awaiting_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: awaiting_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.awaiting_topics_id_seq OWNED BY public.awaiting_topics.id;


--
-- Name: awaitings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.awaitings (
    id bigint NOT NULL,
    title text NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    follow_up_at date NOT NULL,
    resolved_at timestamp(6) without time zone,
    resolution_note text,
    creator_id bigint NOT NULL,
    communication_id bigint,
    task_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    description text,
    contact_uuid character varying
);


--
-- Name: awaitings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.awaitings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: awaitings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.awaitings_id_seq OWNED BY public.awaitings.id;


--
-- Name: bank_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bank_accounts (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    iban character varying,
    bic character varying,
    bank_name character varying,
    holder character varying,
    label character varying,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bank_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bank_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bank_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bank_accounts_id_seq OWNED BY public.bank_accounts.id;


--
-- Name: capabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capabilities (
    id bigint NOT NULL,
    actor_id bigint,
    team_id bigint,
    resource_type character varying NOT NULL,
    actions jsonb DEFAULT '[]'::jsonb NOT NULL,
    effect integer DEFAULT 0 NOT NULL,
    scope jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT capabilities_actor_xor_team CHECK ((((actor_id IS NOT NULL) AND (team_id IS NULL)) OR ((actor_id IS NULL) AND (team_id IS NOT NULL))))
);


--
-- Name: capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.capabilities_id_seq OWNED BY public.capabilities.id;


--
-- Name: comment_reads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_reads (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    task_comment_id bigint NOT NULL,
    read_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: comment_reads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comment_reads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comment_reads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comment_reads_id_seq OWNED BY public.comment_reads.id;


--
-- Name: communication_mentions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communication_mentions (
    id bigint NOT NULL,
    communication_id bigint NOT NULL,
    mentioned_uuid character varying NOT NULL,
    role character varying DEFAULT ''::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: communication_mentions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.communication_mentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: communication_mentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.communication_mentions_id_seq OWNED BY public.communication_mentions.id;


--
-- Name: communication_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communication_topics (
    id bigint NOT NULL,
    communication_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: communication_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.communication_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: communication_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.communication_topics_id_seq OWNED BY public.communication_topics.id;


--
-- Name: communications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communications (
    id bigint NOT NULL,
    type character varying DEFAULT 'Email'::character varying NOT NULL,
    subject character varying,
    body text,
    sent_at timestamp(6) without time zone,
    direction integer DEFAULT 0 NOT NULL,
    external_id character varying NOT NULL,
    oauth_credential_id bigint,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    read_at timestamp(6) without time zone,
    participants jsonb DEFAULT '{}'::jsonb NOT NULL,
    suggested_topic_id bigint,
    suggested_topic_score double precision,
    suggested_topic_decided_at timestamp(6) without time zone,
    portal_visible boolean DEFAULT false NOT NULL,
    tags character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    duration_minutes integer
);


--
-- Name: communications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.communications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: communications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.communications_id_seq OWNED BY public.communications.id;


--
-- Name: contact_points; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_points (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    kind character varying NOT NULL,
    label character varying DEFAULT ''::character varying,
    value text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    billing boolean DEFAULT false NOT NULL
);


--
-- Name: contact_points_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contact_points_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contact_points_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contact_points_id_seq OWNED BY public.contact_points.id;


--
-- Name: document_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_artifacts (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    pdf bytea NOT NULL,
    signed boolean DEFAULT false NOT NULL,
    creator_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    shared_with_client boolean DEFAULT false NOT NULL
);


--
-- Name: document_artifacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_artifacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_artifacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_artifacts_id_seq OWNED BY public.document_artifacts.id;


--
-- Name: document_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_fields (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    label character varying NOT NULL,
    value character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: document_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_fields_id_seq OWNED BY public.document_fields.id;


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    id bigint NOT NULL,
    kind integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    issuer_uuid character varying,
    recipient_uuid character varying,
    body_ki_uuid character varying,
    topic_id bigint,
    creator_id bigint,
    subject character varying,
    salutation character varying,
    number character varying,
    document_date date,
    theme character varying DEFAULT 'din5008_b'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    your_ref character varying,
    our_ref character varying,
    shown_identifier_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    service_start date,
    service_end date,
    recipient_address_id bigint,
    deleted_at timestamp(6) without time zone,
    debtor_bank_account_id bigint
);


--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.documents_id_seq OWNED BY public.documents.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    title character varying NOT NULL,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone,
    location character varying,
    description text,
    topic_id bigint,
    creator_id bigint,
    communication_id bigint,
    portal_visible boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    gcal_event_id character varying
);


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: identifiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identifiers (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    counterparty_uuid character varying,
    label character varying NOT NULL,
    value character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: identifiers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identifiers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identifiers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identifiers_id_seq OWNED BY public.identifiers.id;


--
-- Name: inbox_item_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbox_item_topics (
    id bigint NOT NULL,
    inbox_item_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inbox_item_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inbox_item_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbox_item_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inbox_item_topics_id_seq OWNED BY public.inbox_item_topics.id;


--
-- Name: inbox_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbox_items (
    id bigint NOT NULL,
    source_kind character varying NOT NULL,
    source_url character varying,
    raw_content text,
    external_path character varying,
    title character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    processor_kind character varying,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    processed_at timestamp(6) without time zone,
    creator_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inbox_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inbox_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbox_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inbox_items_id_seq OWNED BY public.inbox_items.id;


--
-- Name: invoice_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_lines (
    id bigint NOT NULL,
    document_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    description character varying,
    unit character varying,
    quantity numeric(12,2) DEFAULT 0.0 NOT NULL,
    unit_price numeric(12,2) DEFAULT 0.0 NOT NULL,
    tax_rate numeric(5,2) DEFAULT 19.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoice_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoice_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoice_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoice_lines_id_seq OWNED BY public.invoice_lines.id;


--
-- Name: ki_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ki_templates (
    id bigint NOT NULL,
    name character varying NOT NULL,
    item_type character varying DEFAULT 'note'::character varying NOT NULL,
    title character varying,
    body text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ki_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ki_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ki_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ki_templates_id_seq OWNED BY public.ki_templates.id;


--
-- Name: knowledge_item_anchors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_item_anchors (
    id bigint NOT NULL,
    anchor character varying NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tags character varying[] DEFAULT '{}'::character varying[]
);


--
-- Name: knowledge_item_anchors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_item_anchors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_item_anchors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_item_anchors_id_seq OWNED BY public.knowledge_item_anchors.id;


--
-- Name: knowledge_item_mentions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_item_mentions (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    mentioned_uuid character varying NOT NULL,
    "position" integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: knowledge_item_mentions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_item_mentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_item_mentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_item_mentions_id_seq OWNED BY public.knowledge_item_mentions.id;


--
-- Name: knowledge_item_pins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_item_pins (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    knowledge_item_id character varying NOT NULL,
    pinned_at timestamp without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: knowledge_item_pins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_item_pins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_item_pins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_item_pins_id_seq OWNED BY public.knowledge_item_pins.id;


--
-- Name: knowledge_item_references; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_item_references (
    id bigint NOT NULL,
    source_uuid character varying NOT NULL,
    target_uuid character varying,
    target_title character varying NOT NULL,
    anchor_type integer DEFAULT 0 NOT NULL,
    anchor_text character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: knowledge_item_references_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_item_references_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_item_references_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_item_references_id_seq OWNED BY public.knowledge_item_references.id;


--
-- Name: knowledge_item_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_item_topics (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    topic_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: knowledge_item_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.knowledge_item_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: knowledge_item_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.knowledge_item_topics_id_seq OWNED BY public.knowledge_item_topics.id;


--
-- Name: knowledge_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_items (
    uuid character varying NOT NULL,
    title character varying,
    item_type integer DEFAULT 0 NOT NULL,
    file_path character varying NOT NULL,
    content_hash character varying NOT NULL,
    file_created_at timestamp(6) without time zone,
    file_updated_at timestamp(6) without time zone,
    indexed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    aliases character varying[] DEFAULT '{}'::character varying[],
    parent_org_uuid character varying,
    first_name character varying,
    last_name character varying,
    tags character varying[] DEFAULT '{}'::character varying[],
    body text,
    search_vector tsvector,
    inbox_item_id bigint,
    bib_source_id bigint,
    locator_label character varying,
    locator_value character varying,
    creator_id bigint,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    parent_type character varying,
    parent_id_int bigint,
    parent_uuid character varying,
    published_at timestamp(6) without time zone,
    superseded_by_uuid character varying,
    superseded_at timestamp(6) without time zone,
    superseded_by_actor_id bigint,
    orcid character varying,
    issuer boolean DEFAULT false NOT NULL,
    vat_exempt boolean DEFAULT false NOT NULL,
    personally_known boolean DEFAULT false NOT NULL,
    render_mode character varying DEFAULT 'markdown'::character varying NOT NULL
);


--
-- Name: llm_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.llm_activities (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    actor_id bigint NOT NULL,
    model character varying,
    prompt_template_slug character varying,
    source_kind character varying,
    source_id character varying,
    result_kind character varying,
    result_id character varying,
    input_summary text,
    output_summary text,
    error_message text,
    input_tokens integer,
    output_tokens integer,
    cost_eur numeric(8,4),
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: llm_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.llm_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: llm_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.llm_activities_id_seq OWNED BY public.llm_activities.id;


--
-- Name: oauth_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_credentials (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    provider character varying DEFAULT 'google'::character varying NOT NULL,
    access_token_ciphertext text,
    refresh_token_ciphertext text,
    expires_at timestamp(6) without time zone,
    scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    email_address character varying NOT NULL,
    label character varying,
    last_history_id character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sync_since timestamp(6) without time zone,
    gcal_calendar_id character varying
);


--
-- Name: oauth_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_credentials_id_seq OWNED BY public.oauth_credentials.id;


--
-- Name: portal_accesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_accesses (
    id bigint NOT NULL,
    topic_id bigint NOT NULL,
    knowledge_item_uuid character varying,
    email character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    last_login_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    locale character varying
);


--
-- Name: portal_accesses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.portal_accesses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: portal_accesses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.portal_accesses_id_seq OWNED BY public.portal_accesses.id;


--
-- Name: postal_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.postal_addresses (
    id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    line1 character varying,
    line2 character varying,
    postal_code character varying,
    city character varying,
    country character varying,
    billing boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    kind integer DEFAULT 0 NOT NULL
);


--
-- Name: postal_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.postal_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: postal_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.postal_addresses_id_seq OWNED BY public.postal_addresses.id;


--
-- Name: prompt_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_templates (
    id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    description text,
    prompt_text text NOT NULL,
    default_model character varying,
    creator_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    output_format character varying DEFAULT 'markdown'::character varying NOT NULL
);


--
-- Name: prompt_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompt_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompt_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompt_templates_id_seq OWNED BY public.prompt_templates.id;


--
-- Name: relation_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relation_types (
    id bigint NOT NULL,
    name character varying NOT NULL,
    inverse_name character varying,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ebene character varying
);


--
-- Name: relation_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.relation_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: relation_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.relation_types_id_seq OWNED BY public.relation_types.id;


--
-- Name: relations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relations (
    id bigint NOT NULL,
    source_uuid character varying NOT NULL,
    source_type character varying NOT NULL,
    target_uuid character varying NOT NULL,
    target_type character varying NOT NULL,
    anchor_id character varying NOT NULL,
    label character varying,
    description text,
    direction character varying DEFAULT 'source_to_target'::character varying NOT NULL,
    recognized_by_id bigint,
    recognized_role character varying,
    recognized_via character varying,
    recognized_at timestamp(6) without time zone,
    orphaned_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    target_block_anchor character varying
);


--
-- Name: relations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.relations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: relations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.relations_id_seq OWNED BY public.relations.id;


--
-- Name: relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relationships (
    id bigint NOT NULL,
    from_uuid character varying NOT NULL,
    to_uuid character varying NOT NULL,
    kind character varying DEFAULT ''::character varying NOT NULL,
    start_at date,
    end_at date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: relationships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.relationships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: relationships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.relationships_id_seq OWNED BY public.relationships.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_id_seq OWNED BY public.settings.id;


--
-- Name: solid_cable_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cable_messages (
    id bigint NOT NULL,
    channel bytea NOT NULL,
    payload bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    channel_hash bigint NOT NULL
);


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cable_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cable_messages_id_seq OWNED BY public.solid_cable_messages.id;


--
-- Name: source_creators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_creators (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    role character varying DEFAULT 'author'::character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    identification character varying DEFAULT 'provisional'::character varying NOT NULL,
    confidence character varying,
    identified_via character varying,
    identified_by_id bigint,
    identified_at timestamp(6) without time zone
);


--
-- Name: source_creators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_creators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_creators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_creators_id_seq OWNED BY public.source_creators.id;


--
-- Name: source_identifiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_identifiers (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    scheme character varying NOT NULL,
    value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: source_identifiers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_identifiers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_identifiers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_identifiers_id_seq OWNED BY public.source_identifiers.id;


--
-- Name: source_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.source_topics (
    id bigint NOT NULL,
    source_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    relevance character varying DEFAULT 'relevant'::character varying NOT NULL,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    reached boolean DEFAULT true NOT NULL
);


--
-- Name: source_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.source_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.source_topics_id_seq OWNED BY public.source_topics.id;


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id bigint NOT NULL,
    slug character varying NOT NULL,
    csl_type character varying NOT NULL,
    title character varying NOT NULL,
    container_title character varying,
    publisher character varying,
    publisher_place character varying,
    issued_date date,
    issued_string character varying,
    accessed date,
    edition character varying,
    volume character varying,
    issue character varying,
    pages character varying,
    abstract text,
    language character varying,
    archive character varying,
    archive_location character varying,
    url character varying,
    parent_source_id bigint,
    jurisdiction character varying,
    court character varying,
    docket_number character varying,
    parallel_citations jsonb DEFAULT '[]'::jsonb,
    creator_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sources_id_seq OWNED BY public.sources.id;


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taggings (
    id bigint NOT NULL,
    tag_id bigint NOT NULL,
    taggable_type character varying NOT NULL,
    taggable_id_int bigint,
    taggable_uuid character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: taggings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.taggings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: taggings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.taggings_id_seq OWNED BY public.taggings.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id bigint NOT NULL,
    name character varying NOT NULL,
    color character varying,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;


--
-- Name: task_anchors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_anchors (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    anchor character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_anchors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_anchors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_anchors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_anchors_id_seq OWNED BY public.task_anchors.id;


--
-- Name: task_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_attachments (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    uploader_id bigint NOT NULL,
    file_path character varying NOT NULL,
    original_filename character varying NOT NULL,
    content_type character varying,
    byte_size bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_attachments_id_seq OWNED BY public.task_attachments.id;


--
-- Name: task_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_comments (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    published_at timestamp(6) without time zone
);


--
-- Name: task_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_comments_id_seq OWNED BY public.task_comments.id;


--
-- Name: task_dependencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_dependencies (
    id bigint NOT NULL,
    predecessor_id bigint NOT NULL,
    successor_id bigint NOT NULL,
    dependency_type integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_dependencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_dependencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_dependencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_dependencies_id_seq OWNED BY public.task_dependencies.id;


--
-- Name: task_mentions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_mentions (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    mentioned_uuid character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_mentions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_mentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_mentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_mentions_id_seq OWNED BY public.task_mentions.id;


--
-- Name: task_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_sources (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    source_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_sources_id_seq OWNED BY public.task_sources.id;


--
-- Name: task_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_templates (
    id bigint NOT NULL,
    title character varying NOT NULL,
    description text,
    agent_actor_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: task_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_templates_id_seq OWNED BY public.task_templates.id;


--
-- Name: task_topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_topics (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    next_step boolean DEFAULT false NOT NULL
);


--
-- Name: task_topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.task_topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: task_topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.task_topics_id_seq OWNED BY public.task_topics.id;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id bigint NOT NULL,
    title character varying NOT NULL,
    description text,
    status integer DEFAULT 0 NOT NULL,
    priority integer DEFAULT 1 NOT NULL,
    due_date date,
    completed_at timestamp(6) without time zone,
    assignee_id bigint,
    creator_id bigint NOT NULL,
    parent_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    communication_id bigint,
    commitment integer,
    deleted_at timestamp(6) without time zone,
    search_vector tsvector,
    inbox_item_id bigint,
    tags character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    published_at timestamp(6) without time zone,
    wip_actor_id bigint,
    client_milestone boolean DEFAULT false NOT NULL
);


--
-- Name: tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasks_id_seq OWNED BY public.tasks.id;


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    role integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: team_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_memberships_id_seq OWNED BY public.team_memberships.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.teams_id_seq OWNED BY public.teams.id;


--
-- Name: time_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_entries (
    id bigint NOT NULL,
    actor_id bigint NOT NULL,
    topic_id bigint,
    subject_type character varying,
    subject_id_int bigint,
    subject_uuid character varying,
    started_at timestamp(6) without time zone NOT NULL,
    ended_at timestamp(6) without time zone,
    billable boolean DEFAULT false NOT NULL,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    invoice_line_id bigint
);


--
-- Name: time_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.time_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: time_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.time_entries_id_seq OWNED BY public.time_entries.id;


--
-- Name: time_segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_segments (
    id bigint NOT NULL,
    time_entry_id bigint NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    ended_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    end_reason character varying
);


--
-- Name: time_segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.time_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: time_segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.time_segments_id_seq OWNED BY public.time_segments.id;


--
-- Name: topic_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.topic_memberships (
    id bigint NOT NULL,
    topic_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: topic_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.topic_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: topic_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.topic_memberships_id_seq OWNED BY public.topic_memberships.id;


--
-- Name: topic_trees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.topic_trees (
    id bigint NOT NULL,
    topic_id bigint NOT NULL,
    kind character varying DEFAULT 'work'::character varying NOT NULL,
    name character varying,
    "position" integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: topic_trees_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.topic_trees_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: topic_trees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.topic_trees_id_seq OWNED BY public.topic_trees.id;


--
-- Name: topics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.topics (
    id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    description text,
    status integer DEFAULT 0 NOT NULL,
    color character varying,
    template boolean DEFAULT false NOT NULL,
    creator_id bigint NOT NULL,
    team_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    parent_topic_id bigint,
    work_tree_title character varying,
    work_tree_subtitle character varying,
    customer_uuid character varying,
    billable boolean DEFAULT false NOT NULL,
    visibility integer DEFAULT 0 NOT NULL
);


--
-- Name: topics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.topics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: topics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.topics_id_seq OWNED BY public.topics.id;


--
-- Name: wikilink_research_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wikilink_research_jobs (
    id bigint NOT NULL,
    source_knowledge_item_id character varying NOT NULL,
    target_title character varying NOT NULL,
    target_source_url character varying,
    task_id bigint NOT NULL,
    target_knowledge_item_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: wikilink_research_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wikilink_research_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wikilink_research_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wikilink_research_jobs_id_seq OWNED BY public.wikilink_research_jobs.id;


--
-- Name: work_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_nodes (
    id bigint NOT NULL,
    topic_id bigint NOT NULL,
    knowledge_item_uuid character varying NOT NULL,
    parent_id bigint,
    "position" integer NOT NULL,
    role character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tree_id bigint NOT NULL,
    junctor character varying,
    chosen boolean DEFAULT false NOT NULL
);


--
-- Name: work_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.work_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: work_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.work_nodes_id_seq OWNED BY public.work_nodes.id;


--
-- Name: actor_mentions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_mentions ALTER COLUMN id SET DEFAULT nextval('public.actor_mentions_id_seq'::regclass);


--
-- Name: actor_views id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_views ALTER COLUMN id SET DEFAULT nextval('public.actor_views_id_seq'::regclass);


--
-- Name: actors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors ALTER COLUMN id SET DEFAULT nextval('public.actors_id_seq'::regclass);


--
-- Name: affiliations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliations ALTER COLUMN id SET DEFAULT nextval('public.affiliations_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: awaiting_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaiting_topics ALTER COLUMN id SET DEFAULT nextval('public.awaiting_topics_id_seq'::regclass);


--
-- Name: awaitings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaitings ALTER COLUMN id SET DEFAULT nextval('public.awaitings_id_seq'::regclass);


--
-- Name: bank_accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_accounts ALTER COLUMN id SET DEFAULT nextval('public.bank_accounts_id_seq'::regclass);


--
-- Name: capabilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities ALTER COLUMN id SET DEFAULT nextval('public.capabilities_id_seq'::regclass);


--
-- Name: comment_reads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reads ALTER COLUMN id SET DEFAULT nextval('public.comment_reads_id_seq'::regclass);


--
-- Name: communication_mentions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_mentions ALTER COLUMN id SET DEFAULT nextval('public.communication_mentions_id_seq'::regclass);


--
-- Name: communication_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_topics ALTER COLUMN id SET DEFAULT nextval('public.communication_topics_id_seq'::regclass);


--
-- Name: communications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communications ALTER COLUMN id SET DEFAULT nextval('public.communications_id_seq'::regclass);


--
-- Name: contact_points id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_points ALTER COLUMN id SET DEFAULT nextval('public.contact_points_id_seq'::regclass);


--
-- Name: document_artifacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_artifacts ALTER COLUMN id SET DEFAULT nextval('public.document_artifacts_id_seq'::regclass);


--
-- Name: document_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_fields ALTER COLUMN id SET DEFAULT nextval('public.document_fields_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents ALTER COLUMN id SET DEFAULT nextval('public.documents_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: identifiers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identifiers ALTER COLUMN id SET DEFAULT nextval('public.identifiers_id_seq'::regclass);


--
-- Name: inbox_item_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item_topics ALTER COLUMN id SET DEFAULT nextval('public.inbox_item_topics_id_seq'::regclass);


--
-- Name: inbox_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_items ALTER COLUMN id SET DEFAULT nextval('public.inbox_items_id_seq'::regclass);


--
-- Name: invoice_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines ALTER COLUMN id SET DEFAULT nextval('public.invoice_lines_id_seq'::regclass);


--
-- Name: ki_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ki_templates ALTER COLUMN id SET DEFAULT nextval('public.ki_templates_id_seq'::regclass);


--
-- Name: knowledge_item_anchors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_anchors ALTER COLUMN id SET DEFAULT nextval('public.knowledge_item_anchors_id_seq'::regclass);


--
-- Name: knowledge_item_mentions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_mentions ALTER COLUMN id SET DEFAULT nextval('public.knowledge_item_mentions_id_seq'::regclass);


--
-- Name: knowledge_item_pins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_pins ALTER COLUMN id SET DEFAULT nextval('public.knowledge_item_pins_id_seq'::regclass);


--
-- Name: knowledge_item_references id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_references ALTER COLUMN id SET DEFAULT nextval('public.knowledge_item_references_id_seq'::regclass);


--
-- Name: knowledge_item_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_topics ALTER COLUMN id SET DEFAULT nextval('public.knowledge_item_topics_id_seq'::regclass);


--
-- Name: llm_activities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.llm_activities ALTER COLUMN id SET DEFAULT nextval('public.llm_activities_id_seq'::regclass);


--
-- Name: oauth_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_credentials ALTER COLUMN id SET DEFAULT nextval('public.oauth_credentials_id_seq'::regclass);


--
-- Name: portal_accesses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_accesses ALTER COLUMN id SET DEFAULT nextval('public.portal_accesses_id_seq'::regclass);


--
-- Name: postal_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postal_addresses ALTER COLUMN id SET DEFAULT nextval('public.postal_addresses_id_seq'::regclass);


--
-- Name: prompt_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_templates ALTER COLUMN id SET DEFAULT nextval('public.prompt_templates_id_seq'::regclass);


--
-- Name: relation_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relation_types ALTER COLUMN id SET DEFAULT nextval('public.relation_types_id_seq'::regclass);


--
-- Name: relations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relations ALTER COLUMN id SET DEFAULT nextval('public.relations_id_seq'::regclass);


--
-- Name: relationships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relationships ALTER COLUMN id SET DEFAULT nextval('public.relationships_id_seq'::regclass);


--
-- Name: settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings ALTER COLUMN id SET DEFAULT nextval('public.settings_id_seq'::regclass);


--
-- Name: solid_cable_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages ALTER COLUMN id SET DEFAULT nextval('public.solid_cable_messages_id_seq'::regclass);


--
-- Name: source_creators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_creators ALTER COLUMN id SET DEFAULT nextval('public.source_creators_id_seq'::regclass);


--
-- Name: source_identifiers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_identifiers ALTER COLUMN id SET DEFAULT nextval('public.source_identifiers_id_seq'::regclass);


--
-- Name: source_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_topics ALTER COLUMN id SET DEFAULT nextval('public.source_topics_id_seq'::regclass);


--
-- Name: sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources ALTER COLUMN id SET DEFAULT nextval('public.sources_id_seq'::regclass);


--
-- Name: taggings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings ALTER COLUMN id SET DEFAULT nextval('public.taggings_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: task_anchors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_anchors ALTER COLUMN id SET DEFAULT nextval('public.task_anchors_id_seq'::regclass);


--
-- Name: task_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments ALTER COLUMN id SET DEFAULT nextval('public.task_attachments_id_seq'::regclass);


--
-- Name: task_comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments ALTER COLUMN id SET DEFAULT nextval('public.task_comments_id_seq'::regclass);


--
-- Name: task_dependencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_dependencies ALTER COLUMN id SET DEFAULT nextval('public.task_dependencies_id_seq'::regclass);


--
-- Name: task_mentions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_mentions ALTER COLUMN id SET DEFAULT nextval('public.task_mentions_id_seq'::regclass);


--
-- Name: task_sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_sources ALTER COLUMN id SET DEFAULT nextval('public.task_sources_id_seq'::regclass);


--
-- Name: task_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates ALTER COLUMN id SET DEFAULT nextval('public.task_templates_id_seq'::regclass);


--
-- Name: task_topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_topics ALTER COLUMN id SET DEFAULT nextval('public.task_topics_id_seq'::regclass);


--
-- Name: tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks ALTER COLUMN id SET DEFAULT nextval('public.tasks_id_seq'::regclass);


--
-- Name: team_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships ALTER COLUMN id SET DEFAULT nextval('public.team_memberships_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams ALTER COLUMN id SET DEFAULT nextval('public.teams_id_seq'::regclass);


--
-- Name: time_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries ALTER COLUMN id SET DEFAULT nextval('public.time_entries_id_seq'::regclass);


--
-- Name: time_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_segments ALTER COLUMN id SET DEFAULT nextval('public.time_segments_id_seq'::regclass);


--
-- Name: topic_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_memberships ALTER COLUMN id SET DEFAULT nextval('public.topic_memberships_id_seq'::regclass);


--
-- Name: topic_trees id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_trees ALTER COLUMN id SET DEFAULT nextval('public.topic_trees_id_seq'::regclass);


--
-- Name: topics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topics ALTER COLUMN id SET DEFAULT nextval('public.topics_id_seq'::regclass);


--
-- Name: wikilink_research_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wikilink_research_jobs ALTER COLUMN id SET DEFAULT nextval('public.wikilink_research_jobs_id_seq'::regclass);


--
-- Name: work_nodes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes ALTER COLUMN id SET DEFAULT nextval('public.work_nodes_id_seq'::regclass);


--
-- Name: actor_mentions actor_mentions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_mentions
    ADD CONSTRAINT actor_mentions_pkey PRIMARY KEY (id);


--
-- Name: actor_views actor_views_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_views
    ADD CONSTRAINT actor_views_pkey PRIMARY KEY (id);


--
-- Name: actors actors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors
    ADD CONSTRAINT actors_pkey PRIMARY KEY (id);


--
-- Name: affiliations affiliations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.affiliations
    ADD CONSTRAINT affiliations_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: awaiting_topics awaiting_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaiting_topics
    ADD CONSTRAINT awaiting_topics_pkey PRIMARY KEY (id);


--
-- Name: awaitings awaitings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaitings
    ADD CONSTRAINT awaitings_pkey PRIMARY KEY (id);


--
-- Name: bank_accounts bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bank_accounts
    ADD CONSTRAINT bank_accounts_pkey PRIMARY KEY (id);


--
-- Name: capabilities capabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities
    ADD CONSTRAINT capabilities_pkey PRIMARY KEY (id);


--
-- Name: comment_reads comment_reads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reads
    ADD CONSTRAINT comment_reads_pkey PRIMARY KEY (id);


--
-- Name: communication_mentions communication_mentions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_mentions
    ADD CONSTRAINT communication_mentions_pkey PRIMARY KEY (id);


--
-- Name: communication_topics communication_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_topics
    ADD CONSTRAINT communication_topics_pkey PRIMARY KEY (id);


--
-- Name: communications communications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communications
    ADD CONSTRAINT communications_pkey PRIMARY KEY (id);


--
-- Name: contact_points contact_points_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_points
    ADD CONSTRAINT contact_points_pkey PRIMARY KEY (id);


--
-- Name: document_artifacts document_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_artifacts
    ADD CONSTRAINT document_artifacts_pkey PRIMARY KEY (id);


--
-- Name: document_fields document_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_fields
    ADD CONSTRAINT document_fields_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: identifiers identifiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identifiers
    ADD CONSTRAINT identifiers_pkey PRIMARY KEY (id);


--
-- Name: inbox_item_topics inbox_item_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item_topics
    ADD CONSTRAINT inbox_item_topics_pkey PRIMARY KEY (id);


--
-- Name: inbox_items inbox_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_items
    ADD CONSTRAINT inbox_items_pkey PRIMARY KEY (id);


--
-- Name: invoice_lines invoice_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines
    ADD CONSTRAINT invoice_lines_pkey PRIMARY KEY (id);


--
-- Name: ki_templates ki_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ki_templates
    ADD CONSTRAINT ki_templates_pkey PRIMARY KEY (id);


--
-- Name: knowledge_item_anchors knowledge_item_anchors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_anchors
    ADD CONSTRAINT knowledge_item_anchors_pkey PRIMARY KEY (id);


--
-- Name: knowledge_item_mentions knowledge_item_mentions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_mentions
    ADD CONSTRAINT knowledge_item_mentions_pkey PRIMARY KEY (id);


--
-- Name: knowledge_item_pins knowledge_item_pins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_pins
    ADD CONSTRAINT knowledge_item_pins_pkey PRIMARY KEY (id);


--
-- Name: knowledge_item_references knowledge_item_references_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_references
    ADD CONSTRAINT knowledge_item_references_pkey PRIMARY KEY (id);


--
-- Name: knowledge_item_topics knowledge_item_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_topics
    ADD CONSTRAINT knowledge_item_topics_pkey PRIMARY KEY (id);


--
-- Name: knowledge_items knowledge_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_items
    ADD CONSTRAINT knowledge_items_pkey PRIMARY KEY (uuid);


--
-- Name: llm_activities llm_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.llm_activities
    ADD CONSTRAINT llm_activities_pkey PRIMARY KEY (id);


--
-- Name: oauth_credentials oauth_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_credentials
    ADD CONSTRAINT oauth_credentials_pkey PRIMARY KEY (id);


--
-- Name: portal_accesses portal_accesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_accesses
    ADD CONSTRAINT portal_accesses_pkey PRIMARY KEY (id);


--
-- Name: postal_addresses postal_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postal_addresses
    ADD CONSTRAINT postal_addresses_pkey PRIMARY KEY (id);


--
-- Name: prompt_templates prompt_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_templates
    ADD CONSTRAINT prompt_templates_pkey PRIMARY KEY (id);


--
-- Name: relation_types relation_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relation_types
    ADD CONSTRAINT relation_types_pkey PRIMARY KEY (id);


--
-- Name: relations relations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relations
    ADD CONSTRAINT relations_pkey PRIMARY KEY (id);


--
-- Name: relationships relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relationships
    ADD CONSTRAINT relationships_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: solid_cable_messages solid_cable_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages
    ADD CONSTRAINT solid_cable_messages_pkey PRIMARY KEY (id);


--
-- Name: source_creators source_creators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_creators
    ADD CONSTRAINT source_creators_pkey PRIMARY KEY (id);


--
-- Name: source_identifiers source_identifiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_identifiers
    ADD CONSTRAINT source_identifiers_pkey PRIMARY KEY (id);


--
-- Name: source_topics source_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_topics
    ADD CONSTRAINT source_topics_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: taggings taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: task_anchors task_anchors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_anchors
    ADD CONSTRAINT task_anchors_pkey PRIMARY KEY (id);


--
-- Name: task_attachments task_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT task_attachments_pkey PRIMARY KEY (id);


--
-- Name: task_comments task_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT task_comments_pkey PRIMARY KEY (id);


--
-- Name: task_dependencies task_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_dependencies
    ADD CONSTRAINT task_dependencies_pkey PRIMARY KEY (id);


--
-- Name: task_mentions task_mentions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_mentions
    ADD CONSTRAINT task_mentions_pkey PRIMARY KEY (id);


--
-- Name: task_sources task_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_sources
    ADD CONSTRAINT task_sources_pkey PRIMARY KEY (id);


--
-- Name: task_templates task_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates
    ADD CONSTRAINT task_templates_pkey PRIMARY KEY (id);


--
-- Name: task_topics task_topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_topics
    ADD CONSTRAINT task_topics_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: team_memberships team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT team_memberships_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: time_entries time_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT time_entries_pkey PRIMARY KEY (id);


--
-- Name: time_segments time_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_segments
    ADD CONSTRAINT time_segments_pkey PRIMARY KEY (id);


--
-- Name: topic_memberships topic_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_memberships
    ADD CONSTRAINT topic_memberships_pkey PRIMARY KEY (id);


--
-- Name: topic_trees topic_trees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_trees
    ADD CONSTRAINT topic_trees_pkey PRIMARY KEY (id);


--
-- Name: topics topics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT topics_pkey PRIMARY KEY (id);


--
-- Name: wikilink_research_jobs wikilink_research_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wikilink_research_jobs
    ADD CONSTRAINT wikilink_research_jobs_pkey PRIMARY KEY (id);


--
-- Name: work_nodes work_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes
    ADD CONSTRAINT work_nodes_pkey PRIMARY KEY (id);


--
-- Name: idx_actor_views_by_actor_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actor_views_by_actor_time ON public.actor_views USING btree (actor_id, viewed_at DESC);


--
-- Name: idx_actor_views_dedupe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_actor_views_dedupe ON public.actor_views USING btree (actor_id, viewable_type, viewable_id, viewed_at);


--
-- Name: idx_cm_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_cm_unique ON public.communication_mentions USING btree (communication_id, mentioned_uuid, role);


--
-- Name: idx_contact_points_lower_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_points_lower_value ON public.contact_points USING btree (lower(value));


--
-- Name: idx_kim_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_kim_unique ON public.knowledge_item_mentions USING btree (knowledge_item_uuid, mentioned_uuid);


--
-- Name: idx_kis_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_kis_search_vector ON public.knowledge_items USING gin (search_vector);


--
-- Name: idx_on_knowledge_item_uuid_kind_position_46814bd079; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_knowledge_item_uuid_kind_position_46814bd079 ON public.contact_points USING btree (knowledge_item_uuid, kind, "position");


--
-- Name: idx_pins_actor_ki_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pins_actor_ki_unique ON public.knowledge_item_pins USING btree (actor_id, knowledge_item_id);


--
-- Name: idx_source_identifiers_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_source_identifiers_uniq ON public.source_identifiers USING btree (source_id, scheme, value);


--
-- Name: idx_taggings_ki; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taggings_ki ON public.taggings USING btree (taggable_type, taggable_uuid);


--
-- Name: idx_taggings_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taggings_task ON public.taggings USING btree (taggable_type, taggable_id_int);


--
-- Name: idx_taggings_unique_ki; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_taggings_unique_ki ON public.taggings USING btree (tag_id, taggable_type, taggable_uuid) WHERE (taggable_uuid IS NOT NULL);


--
-- Name: idx_taggings_unique_task; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_taggings_unique_task ON public.taggings USING btree (tag_id, taggable_type, taggable_id_int) WHERE (taggable_id_int IS NOT NULL);


--
-- Name: idx_tasks_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_search_vector ON public.tasks USING gin (search_vector);


--
-- Name: idx_tm_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tm_unique ON public.task_mentions USING btree (task_id, mentioned_uuid);


--
-- Name: idx_wikilink_jobs_source_title_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wikilink_jobs_source_title_unique ON public.wikilink_research_jobs USING btree (source_knowledge_item_id, target_title);


--
-- Name: index_actor_mentions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actor_mentions_on_actor_id ON public.actor_mentions USING btree (actor_id);


--
-- Name: index_actor_mentions_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_actor_mentions_pair ON public.actor_mentions USING btree (knowledge_item_uuid, actor_id);


--
-- Name: index_actor_views_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actor_views_on_actor_id ON public.actor_views USING btree (actor_id);


--
-- Name: index_actor_views_on_viewable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actor_views_on_viewable ON public.actor_views USING btree (viewable_type, viewable_id);


--
-- Name: index_actors_on_api_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_actors_on_api_token ON public.actors USING btree (api_token) WHERE (api_token IS NOT NULL);


--
-- Name: index_actors_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actors_on_email ON public.actors USING btree (email) WHERE (email IS NOT NULL);


--
-- Name: index_actors_on_person_ki_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actors_on_person_ki_uuid ON public.actors USING btree (person_ki_uuid);


--
-- Name: index_actors_on_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actors_on_type ON public.actors USING btree (type);


--
-- Name: index_affiliations_on_organization_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_affiliations_on_organization_uuid ON public.affiliations USING btree (organization_uuid);


--
-- Name: index_affiliations_on_person_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_affiliations_on_person_uuid ON public.affiliations USING btree (person_uuid);


--
-- Name: index_affiliations_unique_combo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_affiliations_unique_combo ON public.affiliations USING btree (person_uuid, organization_uuid, role, start_at);


--
-- Name: index_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_action ON public.audit_logs USING btree (action);


--
-- Name: index_audit_logs_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_actor_id ON public.audit_logs USING btree (actor_id);


--
-- Name: index_audit_logs_on_auditable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_auditable ON public.audit_logs USING btree (auditable_type, auditable_id);


--
-- Name: index_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_created_at ON public.audit_logs USING btree (created_at);


--
-- Name: index_awaiting_topics_on_awaiting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaiting_topics_on_awaiting_id ON public.awaiting_topics USING btree (awaiting_id);


--
-- Name: index_awaiting_topics_on_awaiting_id_and_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_awaiting_topics_on_awaiting_id_and_topic_id ON public.awaiting_topics USING btree (awaiting_id, topic_id);


--
-- Name: index_awaiting_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaiting_topics_on_topic_id ON public.awaiting_topics USING btree (topic_id);


--
-- Name: index_awaitings_on_communication_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaitings_on_communication_id ON public.awaitings USING btree (communication_id);


--
-- Name: index_awaitings_on_contact_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaitings_on_contact_uuid ON public.awaitings USING btree (contact_uuid);


--
-- Name: index_awaitings_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaitings_on_creator_id ON public.awaitings USING btree (creator_id);


--
-- Name: index_awaitings_on_status_and_follow_up_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaitings_on_status_and_follow_up_at ON public.awaitings USING btree (status, follow_up_at);


--
-- Name: index_awaitings_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_awaitings_on_task_id ON public.awaitings USING btree (task_id);


--
-- Name: index_bank_accounts_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bank_accounts_on_knowledge_item_uuid ON public.bank_accounts USING btree (knowledge_item_uuid);


--
-- Name: index_capabilities_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_capabilities_on_actor_id ON public.capabilities USING btree (actor_id);


--
-- Name: index_capabilities_on_actor_resource_effect; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_capabilities_on_actor_resource_effect ON public.capabilities USING btree (actor_id, resource_type, effect) WHERE (actor_id IS NOT NULL);


--
-- Name: index_capabilities_on_resource_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_capabilities_on_resource_type ON public.capabilities USING btree (resource_type);


--
-- Name: index_capabilities_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_capabilities_on_team_id ON public.capabilities USING btree (team_id);


--
-- Name: index_capabilities_on_team_resource_effect; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_capabilities_on_team_resource_effect ON public.capabilities USING btree (team_id, resource_type, effect) WHERE (team_id IS NOT NULL);


--
-- Name: index_comment_reads_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comment_reads_on_actor_id ON public.comment_reads USING btree (actor_id);


--
-- Name: index_comment_reads_on_actor_id_and_task_comment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_comment_reads_on_actor_id_and_task_comment_id ON public.comment_reads USING btree (actor_id, task_comment_id);


--
-- Name: index_comment_reads_on_task_comment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comment_reads_on_task_comment_id ON public.comment_reads USING btree (task_comment_id);


--
-- Name: index_communication_mentions_on_communication_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communication_mentions_on_communication_id ON public.communication_mentions USING btree (communication_id);


--
-- Name: index_communication_mentions_on_mentioned_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communication_mentions_on_mentioned_uuid ON public.communication_mentions USING btree (mentioned_uuid);


--
-- Name: index_communication_topics_on_communication_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communication_topics_on_communication_id ON public.communication_topics USING btree (communication_id);


--
-- Name: index_communication_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communication_topics_on_topic_id ON public.communication_topics USING btree (topic_id);


--
-- Name: index_communications_on_direction; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_direction ON public.communications USING btree (direction);


--
-- Name: index_communications_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_communications_on_external_id ON public.communications USING btree (external_id);


--
-- Name: index_communications_on_oauth_credential_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_oauth_credential_id ON public.communications USING btree (oauth_credential_id);


--
-- Name: index_communications_on_read_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_read_at ON public.communications USING btree (read_at);


--
-- Name: index_communications_on_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_sent_at ON public.communications USING btree (sent_at);


--
-- Name: index_communications_on_suggested_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_suggested_topic_id ON public.communications USING btree (suggested_topic_id);


--
-- Name: index_communications_on_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_communications_on_type ON public.communications USING btree (type);


--
-- Name: index_contact_points_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contact_points_on_kind ON public.contact_points USING btree (kind);


--
-- Name: index_contact_points_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contact_points_on_knowledge_item_uuid ON public.contact_points USING btree (knowledge_item_uuid);


--
-- Name: index_ct_on_comm_and_topic; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ct_on_comm_and_topic ON public.communication_topics USING btree (communication_id, topic_id);


--
-- Name: index_document_artifacts_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_artifacts_on_document_id ON public.document_artifacts USING btree (document_id);


--
-- Name: index_document_fields_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_fields_on_document_id ON public.document_fields USING btree (document_id);


--
-- Name: index_documents_on_body_ki_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_body_ki_uuid ON public.documents USING btree (body_ki_uuid);


--
-- Name: index_documents_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_deleted_at ON public.documents USING btree (deleted_at);


--
-- Name: index_documents_on_issuer_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_issuer_uuid ON public.documents USING btree (issuer_uuid);


--
-- Name: index_documents_on_kind_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_kind_and_status ON public.documents USING btree (kind, status);


--
-- Name: index_documents_on_recipient_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_recipient_uuid ON public.documents USING btree (recipient_uuid);


--
-- Name: index_documents_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_documents_on_topic_id ON public.documents USING btree (topic_id);


--
-- Name: index_events_on_communication_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_communication_id ON public.events USING btree (communication_id);


--
-- Name: index_events_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_creator_id ON public.events USING btree (creator_id);


--
-- Name: index_events_on_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_starts_at ON public.events USING btree (starts_at);


--
-- Name: index_events_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_topic_id ON public.events USING btree (topic_id);


--
-- Name: index_identifiers_on_counterparty_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identifiers_on_counterparty_uuid ON public.identifiers USING btree (counterparty_uuid);


--
-- Name: index_identifiers_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identifiers_on_knowledge_item_uuid ON public.identifiers USING btree (knowledge_item_uuid);


--
-- Name: index_inbox_item_topics_on_inbox_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_item_topics_on_inbox_item_id ON public.inbox_item_topics USING btree (inbox_item_id);


--
-- Name: index_inbox_item_topics_on_inbox_item_id_and_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbox_item_topics_on_inbox_item_id_and_topic_id ON public.inbox_item_topics USING btree (inbox_item_id, topic_id);


--
-- Name: index_inbox_item_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_item_topics_on_topic_id ON public.inbox_item_topics USING btree (topic_id);


--
-- Name: index_inbox_items_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_items_on_created_at ON public.inbox_items USING btree (created_at);


--
-- Name: index_inbox_items_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_items_on_creator_id ON public.inbox_items USING btree (creator_id);


--
-- Name: index_inbox_items_on_source_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_items_on_source_kind ON public.inbox_items USING btree (source_kind);


--
-- Name: index_inbox_items_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_items_on_status ON public.inbox_items USING btree (status);


--
-- Name: index_invoice_lines_on_document_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_lines_on_document_id ON public.invoice_lines USING btree (document_id);


--
-- Name: index_ki_on_parent_int; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ki_on_parent_int ON public.knowledge_items USING btree (parent_type, parent_id_int);


--
-- Name: index_ki_on_parent_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ki_on_parent_uuid ON public.knowledge_items USING btree (parent_type, parent_uuid);


--
-- Name: index_ki_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ki_on_published_at ON public.knowledge_items USING btree (published_at);


--
-- Name: index_ki_templates_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ki_templates_on_name ON public.ki_templates USING btree (name);


--
-- Name: index_kit_on_item_and_topic; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_kit_on_item_and_topic ON public.knowledge_item_topics USING btree (knowledge_item_uuid, topic_id);


--
-- Name: index_knowledge_item_anchors_on_anchor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_knowledge_item_anchors_on_anchor ON public.knowledge_item_anchors USING btree (anchor);


--
-- Name: index_knowledge_item_anchors_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_anchors_on_knowledge_item_uuid ON public.knowledge_item_anchors USING btree (knowledge_item_uuid);


--
-- Name: index_knowledge_item_mentions_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_mentions_on_knowledge_item_uuid ON public.knowledge_item_mentions USING btree (knowledge_item_uuid);


--
-- Name: index_knowledge_item_mentions_on_mentioned_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_mentions_on_mentioned_uuid ON public.knowledge_item_mentions USING btree (mentioned_uuid);


--
-- Name: index_knowledge_item_pins_on_actor_id_and_pinned_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_pins_on_actor_id_and_pinned_at ON public.knowledge_item_pins USING btree (actor_id, pinned_at);


--
-- Name: index_knowledge_item_references_on_source_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_references_on_source_uuid ON public.knowledge_item_references USING btree (source_uuid);


--
-- Name: index_knowledge_item_references_on_target_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_references_on_target_title ON public.knowledge_item_references USING btree (target_title);


--
-- Name: index_knowledge_item_references_on_target_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_references_on_target_uuid ON public.knowledge_item_references USING btree (target_uuid);


--
-- Name: index_knowledge_item_topics_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_topics_on_knowledge_item_uuid ON public.knowledge_item_topics USING btree (knowledge_item_uuid);


--
-- Name: index_knowledge_item_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_item_topics_on_topic_id ON public.knowledge_item_topics USING btree (topic_id);


--
-- Name: index_knowledge_items_on_aliases; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_aliases ON public.knowledge_items USING gin (aliases);


--
-- Name: index_knowledge_items_on_bib_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_bib_source_id ON public.knowledge_items USING btree (bib_source_id);


--
-- Name: index_knowledge_items_on_content_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_content_hash ON public.knowledge_items USING btree (content_hash);


--
-- Name: index_knowledge_items_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_creator_id ON public.knowledge_items USING btree (creator_id);


--
-- Name: index_knowledge_items_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_deleted_at ON public.knowledge_items USING btree (deleted_at);


--
-- Name: index_knowledge_items_on_file_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_knowledge_items_on_file_path ON public.knowledge_items USING btree (file_path);


--
-- Name: index_knowledge_items_on_inbox_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_inbox_item_id ON public.knowledge_items USING btree (inbox_item_id);


--
-- Name: index_knowledge_items_on_issuer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_issuer ON public.knowledge_items USING btree (issuer) WHERE issuer;


--
-- Name: index_knowledge_items_on_item_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_item_type ON public.knowledge_items USING btree (item_type);


--
-- Name: index_knowledge_items_on_last_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_last_name ON public.knowledge_items USING btree (last_name);


--
-- Name: index_knowledge_items_on_orcid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_orcid ON public.knowledge_items USING btree (orcid) WHERE (orcid IS NOT NULL);


--
-- Name: index_knowledge_items_on_parent_org_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_parent_org_uuid ON public.knowledge_items USING btree (parent_org_uuid);


--
-- Name: index_knowledge_items_on_provenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_provenance ON public.knowledge_items USING gin (provenance);


--
-- Name: index_knowledge_items_on_superseded_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_superseded_by_uuid ON public.knowledge_items USING btree (superseded_by_uuid);


--
-- Name: index_knowledge_items_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_tags ON public.knowledge_items USING gin (tags);


--
-- Name: index_knowledge_items_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_knowledge_items_on_title ON public.knowledge_items USING btree (title);


--
-- Name: index_llm_activities_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_llm_activities_on_actor_id ON public.llm_activities USING btree (actor_id);


--
-- Name: index_llm_activities_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_llm_activities_on_created_at ON public.llm_activities USING btree (created_at);


--
-- Name: index_llm_activities_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_llm_activities_on_kind ON public.llm_activities USING btree (kind);


--
-- Name: index_llm_activities_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_llm_activities_on_status ON public.llm_activities USING btree (status);


--
-- Name: index_oauth_credentials_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_credentials_on_active ON public.oauth_credentials USING btree (active);


--
-- Name: index_oauth_credentials_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_credentials_on_actor_id ON public.oauth_credentials USING btree (actor_id);


--
-- Name: index_oauth_credentials_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_credentials_on_email_address ON public.oauth_credentials USING btree (email_address);


--
-- Name: index_oauth_credentials_on_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_credentials_on_provider ON public.oauth_credentials USING btree (provider);


--
-- Name: index_portal_accesses_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_accesses_on_email ON public.portal_accesses USING btree (email);


--
-- Name: index_portal_accesses_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_accesses_on_topic_id ON public.portal_accesses USING btree (topic_id);


--
-- Name: index_portal_accesses_on_topic_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_accesses_on_topic_id_and_email ON public.portal_accesses USING btree (topic_id, email);


--
-- Name: index_postal_addresses_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_postal_addresses_on_knowledge_item_uuid ON public.postal_addresses USING btree (knowledge_item_uuid);


--
-- Name: index_prompt_templates_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_prompt_templates_on_creator_id ON public.prompt_templates USING btree (creator_id);


--
-- Name: index_prompt_templates_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_prompt_templates_on_slug ON public.prompt_templates USING btree (slug);


--
-- Name: index_relation_types_on_ebene; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relation_types_on_ebene ON public.relation_types USING btree (ebene);


--
-- Name: index_relation_types_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_relation_types_on_lower_name ON public.relation_types USING btree (lower((name)::text));


--
-- Name: index_relations_on_orphaned_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relations_on_orphaned_at ON public.relations USING btree (orphaned_at) WHERE (orphaned_at IS NOT NULL);


--
-- Name: index_relations_on_recognized_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relations_on_recognized_by_id ON public.relations USING btree (recognized_by_id);


--
-- Name: index_relations_on_source_type_and_source_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relations_on_source_type_and_source_uuid ON public.relations USING btree (source_type, source_uuid);


--
-- Name: index_relations_on_source_uuid_and_anchor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_relations_on_source_uuid_and_anchor_id ON public.relations USING btree (source_uuid, anchor_id);


--
-- Name: index_relations_on_target_type_and_target_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relations_on_target_type_and_target_uuid ON public.relations USING btree (target_type, target_uuid);


--
-- Name: index_relationships_on_from_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relationships_on_from_uuid ON public.relationships USING btree (from_uuid);


--
-- Name: index_relationships_on_to_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relationships_on_to_uuid ON public.relationships USING btree (to_uuid);


--
-- Name: index_relationships_unique_combo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_relationships_unique_combo ON public.relationships USING btree (from_uuid, to_uuid, kind, start_at);


--
-- Name: index_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_settings_on_key ON public.settings USING btree (key);


--
-- Name: index_solid_cable_messages_on_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel ON public.solid_cable_messages USING btree (channel);


--
-- Name: index_solid_cable_messages_on_channel_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel_hash ON public.solid_cable_messages USING btree (channel_hash);


--
-- Name: index_solid_cable_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_created_at ON public.solid_cable_messages USING btree (created_at);


--
-- Name: index_source_creators_on_identification; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_creators_on_identification ON public.source_creators USING btree (identification);


--
-- Name: index_source_creators_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_creators_on_knowledge_item_uuid ON public.source_creators USING btree (knowledge_item_uuid);


--
-- Name: index_source_creators_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_creators_on_source_id ON public.source_creators USING btree (source_id);


--
-- Name: index_source_creators_on_source_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_creators_on_source_id_and_position ON public.source_creators USING btree (source_id, "position");


--
-- Name: index_source_identifiers_on_scheme_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_identifiers_on_scheme_and_value ON public.source_identifiers USING btree (scheme, value);


--
-- Name: index_source_identifiers_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_identifiers_on_source_id ON public.source_identifiers USING btree (source_id);


--
-- Name: index_source_topics_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_topics_on_source_id ON public.source_topics USING btree (source_id);


--
-- Name: index_source_topics_on_source_id_and_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_source_topics_on_source_id_and_topic_id ON public.source_topics USING btree (source_id, topic_id);


--
-- Name: index_source_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_source_topics_on_topic_id ON public.source_topics USING btree (topic_id);


--
-- Name: index_sources_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_creator_id ON public.sources USING btree (creator_id);


--
-- Name: index_sources_on_csl_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_csl_type ON public.sources USING btree (csl_type);


--
-- Name: index_sources_on_issued_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_issued_date ON public.sources USING btree (issued_date);


--
-- Name: index_sources_on_lower_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_lower_title ON public.sources USING btree (lower((title)::text));


--
-- Name: index_sources_on_parent_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_parent_source_id ON public.sources USING btree (parent_source_id);


--
-- Name: index_sources_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sources_on_slug ON public.sources USING btree (slug);


--
-- Name: index_taggings_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tag_id ON public.taggings USING btree (tag_id);


--
-- Name: index_tags_on_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tags_on_lower_name ON public.tags USING btree (lower((name)::text));


--
-- Name: index_task_anchors_on_anchor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_anchors_on_anchor ON public.task_anchors USING btree (anchor);


--
-- Name: index_task_anchors_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_anchors_on_task_id ON public.task_anchors USING btree (task_id);


--
-- Name: index_task_attachments_on_file_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_attachments_on_file_path ON public.task_attachments USING btree (file_path);


--
-- Name: index_task_attachments_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_attachments_on_task_id ON public.task_attachments USING btree (task_id);


--
-- Name: index_task_attachments_on_uploader_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_attachments_on_uploader_id ON public.task_attachments USING btree (uploader_id);


--
-- Name: index_task_comments_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_comments_on_actor_id ON public.task_comments USING btree (actor_id);


--
-- Name: index_task_comments_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_comments_on_published_at ON public.task_comments USING btree (published_at);


--
-- Name: index_task_comments_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_comments_on_task_id ON public.task_comments USING btree (task_id);


--
-- Name: index_task_comments_on_task_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_comments_on_task_id_and_created_at ON public.task_comments USING btree (task_id, created_at);


--
-- Name: index_task_dependencies_on_predecessor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_dependencies_on_predecessor_id ON public.task_dependencies USING btree (predecessor_id);


--
-- Name: index_task_dependencies_on_predecessor_id_and_successor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_dependencies_on_predecessor_id_and_successor_id ON public.task_dependencies USING btree (predecessor_id, successor_id);


--
-- Name: index_task_dependencies_on_successor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_dependencies_on_successor_id ON public.task_dependencies USING btree (successor_id);


--
-- Name: index_task_mentions_on_mentioned_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_mentions_on_mentioned_uuid ON public.task_mentions USING btree (mentioned_uuid);


--
-- Name: index_task_mentions_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_mentions_on_task_id ON public.task_mentions USING btree (task_id);


--
-- Name: index_task_sources_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_sources_on_source_id ON public.task_sources USING btree (source_id);


--
-- Name: index_task_sources_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_sources_on_task_id ON public.task_sources USING btree (task_id);


--
-- Name: index_task_sources_on_task_id_and_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_sources_on_task_id_and_source_id ON public.task_sources USING btree (task_id, source_id);


--
-- Name: index_task_templates_on_agent_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_templates_on_agent_actor_id ON public.task_templates USING btree (agent_actor_id);


--
-- Name: index_task_templates_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_templates_on_title ON public.task_templates USING btree (title);


--
-- Name: index_task_topics_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_topics_on_task_id ON public.task_topics USING btree (task_id);


--
-- Name: index_task_topics_on_task_id_and_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_topics_on_task_id_and_topic_id ON public.task_topics USING btree (task_id, topic_id);


--
-- Name: index_task_topics_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_topics_on_topic_id ON public.task_topics USING btree (topic_id);


--
-- Name: index_task_topics_on_topic_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_task_topics_on_topic_id_and_position ON public.task_topics USING btree (topic_id, "position");


--
-- Name: index_task_topics_on_topic_id_next_step; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_task_topics_on_topic_id_next_step ON public.task_topics USING btree (topic_id) WHERE (next_step = true);


--
-- Name: index_tasks_on_assignee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_assignee_id ON public.tasks USING btree (assignee_id);


--
-- Name: index_tasks_on_assignee_id_and_commitment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_assignee_id_and_commitment ON public.tasks USING btree (assignee_id, commitment);


--
-- Name: index_tasks_on_communication_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_communication_id ON public.tasks USING btree (communication_id);


--
-- Name: index_tasks_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_creator_id ON public.tasks USING btree (creator_id);


--
-- Name: index_tasks_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_deleted_at ON public.tasks USING btree (deleted_at);


--
-- Name: index_tasks_on_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_due_date ON public.tasks USING btree (due_date);


--
-- Name: index_tasks_on_inbox_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_inbox_item_id ON public.tasks USING btree (inbox_item_id);


--
-- Name: index_tasks_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_parent_id ON public.tasks USING btree (parent_id);


--
-- Name: index_tasks_on_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_priority ON public.tasks USING btree (priority);


--
-- Name: index_tasks_on_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_published_at ON public.tasks USING btree (published_at);


--
-- Name: index_tasks_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_status ON public.tasks USING btree (status);


--
-- Name: index_tasks_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_tags ON public.tasks USING gin (tags);


--
-- Name: index_tasks_on_wip_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_wip_actor_id ON public.tasks USING btree (wip_actor_id);


--
-- Name: index_tasks_on_wip_actor_id_not_null; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_wip_actor_id_not_null ON public.tasks USING btree (wip_actor_id) WHERE (wip_actor_id IS NOT NULL);


--
-- Name: index_team_memberships_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_actor_id ON public.team_memberships USING btree (actor_id);


--
-- Name: index_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_team_id ON public.team_memberships USING btree (team_id);


--
-- Name: index_team_memberships_on_team_id_and_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_memberships_on_team_id_and_actor_id ON public.team_memberships USING btree (team_id, actor_id);


--
-- Name: index_time_entries_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_actor_id ON public.time_entries USING btree (actor_id);


--
-- Name: index_time_entries_on_actor_id_and_ended_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_actor_id_and_ended_at ON public.time_entries USING btree (actor_id, ended_at);


--
-- Name: index_time_entries_on_actor_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_actor_id_and_status ON public.time_entries USING btree (actor_id, status);


--
-- Name: index_time_entries_on_invoice_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_invoice_line_id ON public.time_entries USING btree (invoice_line_id);


--
-- Name: index_time_entries_on_subject_type_and_subject_id_int; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_subject_type_and_subject_id_int ON public.time_entries USING btree (subject_type, subject_id_int);


--
-- Name: index_time_entries_on_subject_type_and_subject_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_subject_type_and_subject_uuid ON public.time_entries USING btree (subject_type, subject_uuid);


--
-- Name: index_time_entries_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_entries_on_topic_id ON public.time_entries USING btree (topic_id);


--
-- Name: index_time_segments_on_time_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_segments_on_time_entry_id ON public.time_segments USING btree (time_entry_id);


--
-- Name: index_time_segments_on_time_entry_id_and_ended_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_time_segments_on_time_entry_id_and_ended_at ON public.time_segments USING btree (time_entry_id, ended_at);


--
-- Name: index_topic_memberships_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topic_memberships_on_actor_id ON public.topic_memberships USING btree (actor_id);


--
-- Name: index_topic_memberships_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topic_memberships_on_topic_id ON public.topic_memberships USING btree (topic_id);


--
-- Name: index_topic_memberships_on_topic_id_and_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_topic_memberships_on_topic_id_and_actor_id ON public.topic_memberships USING btree (topic_id, actor_id);


--
-- Name: index_topic_trees_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topic_trees_on_topic_id ON public.topic_trees USING btree (topic_id);


--
-- Name: index_topics_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_creator_id ON public.topics USING btree (creator_id);


--
-- Name: index_topics_on_customer_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_customer_uuid ON public.topics USING btree (customer_uuid);


--
-- Name: index_topics_on_parent_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_parent_topic_id ON public.topics USING btree (parent_topic_id);


--
-- Name: index_topics_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_topics_on_slug ON public.topics USING btree (slug);


--
-- Name: index_topics_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_status ON public.topics USING btree (status);


--
-- Name: index_topics_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_team_id ON public.topics USING btree (team_id);


--
-- Name: index_topics_on_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_topics_on_template ON public.topics USING btree (template);


--
-- Name: index_wikilink_research_jobs_on_source_knowledge_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wikilink_research_jobs_on_source_knowledge_item_id ON public.wikilink_research_jobs USING btree (source_knowledge_item_id);


--
-- Name: index_wikilink_research_jobs_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wikilink_research_jobs_on_task_id ON public.wikilink_research_jobs USING btree (task_id);


--
-- Name: index_work_nodes_on_knowledge_item_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_knowledge_item_uuid ON public.work_nodes USING btree (knowledge_item_uuid);


--
-- Name: index_work_nodes_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_parent_id ON public.work_nodes USING btree (parent_id);


--
-- Name: index_work_nodes_on_topic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_topic_id ON public.work_nodes USING btree (topic_id);


--
-- Name: index_work_nodes_on_topic_id_and_knowledge_item_uuid_and_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_topic_id_and_knowledge_item_uuid_and_role ON public.work_nodes USING btree (topic_id, knowledge_item_uuid, role);


--
-- Name: index_work_nodes_on_topic_id_and_parent_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_topic_id_and_parent_id_and_position ON public.work_nodes USING btree (topic_id, parent_id, "position");


--
-- Name: index_work_nodes_on_tree_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_work_nodes_on_tree_id ON public.work_nodes USING btree (tree_id);


--
-- Name: knowledge_items knowledge_items_search_vector_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER knowledge_items_search_vector_trigger BEFORE INSERT OR UPDATE OF title, aliases, tags, body ON public.knowledge_items FOR EACH ROW EXECUTE FUNCTION public.knowledge_items_search_vector_update();


--
-- Name: tasks tasks_search_vector_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tasks_search_vector_trigger BEFORE INSERT OR UPDATE OF title, description ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.tasks_search_vector_update();


--
-- Name: tasks fk_rails_0016c50613; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_0016c50613 FOREIGN KEY (assignee_id) REFERENCES public.actors(id);


--
-- Name: tasks fk_rails_00f6e5b7b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_00f6e5b7b4 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: document_artifacts fk_rails_0c4b35beeb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_artifacts
    ADD CONSTRAINT fk_rails_0c4b35beeb FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: awaitings fk_rails_10022d3f6e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaitings
    ADD CONSTRAINT fk_rails_10022d3f6e FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: wikilink_research_jobs fk_rails_15c069e647; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wikilink_research_jobs
    ADD CONSTRAINT fk_rails_15c069e647 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: events fk_rails_15c34a9137; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_15c34a9137 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: actor_mentions fk_rails_1dbb3b3dc8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_mentions
    ADD CONSTRAINT fk_rails_1dbb3b3dc8 FOREIGN KEY (knowledge_item_uuid) REFERENCES public.knowledge_items(uuid);


--
-- Name: relations fk_rails_1e267d66bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relations
    ADD CONSTRAINT fk_rails_1e267d66bc FOREIGN KEY (recognized_by_id) REFERENCES public.actors(id);


--
-- Name: communications fk_rails_1f2ae2154c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communications
    ADD CONSTRAINT fk_rails_1f2ae2154c FOREIGN KEY (suggested_topic_id) REFERENCES public.topics(id);


--
-- Name: knowledge_item_pins fk_rails_207ac0d618; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_pins
    ADD CONSTRAINT fk_rails_207ac0d618 FOREIGN KEY (knowledge_item_id) REFERENCES public.knowledge_items(uuid);


--
-- Name: knowledge_item_references fk_rails_240f267909; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_references
    ADD CONSTRAINT fk_rails_240f267909 FOREIGN KEY (source_uuid) REFERENCES public.knowledge_items(uuid) ON DELETE CASCADE;


--
-- Name: time_entries fk_rails_29a0387740; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_29a0387740 FOREIGN KEY (invoice_line_id) REFERENCES public.invoice_lines(id);


--
-- Name: communication_topics fk_rails_29e492b377; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_topics
    ADD CONSTRAINT fk_rails_29e492b377 FOREIGN KEY (communication_id) REFERENCES public.communications(id);


--
-- Name: tasks fk_rails_2a82938e21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_2a82938e21 FOREIGN KEY (wip_actor_id) REFERENCES public.actors(id);


--
-- Name: audit_logs fk_rails_2c3f85fdd5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_2c3f85fdd5 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: prompt_templates fk_rails_2d6cc235b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_templates
    ADD CONSTRAINT fk_rails_2d6cc235b8 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: knowledge_items fk_rails_2f941b1824; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_items
    ADD CONSTRAINT fk_rails_2f941b1824 FOREIGN KEY (bib_source_id) REFERENCES public.sources(id);


--
-- Name: task_dependencies fk_rails_2fb4ee459a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_dependencies
    ADD CONSTRAINT fk_rails_2fb4ee459a FOREIGN KEY (predecessor_id) REFERENCES public.tasks(id);


--
-- Name: task_comments fk_rails_316b563a4b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT fk_rails_316b563a4b FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: source_creators fk_rails_3dfb0e5cab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_creators
    ADD CONSTRAINT fk_rails_3dfb0e5cab FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: sources fk_rails_3fa99322ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT fk_rails_3fa99322ee FOREIGN KEY (parent_source_id) REFERENCES public.sources(id);


--
-- Name: team_memberships fk_rails_416666e6de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_416666e6de FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: knowledge_item_references fk_rails_4cbddb1981; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_references
    ADD CONSTRAINT fk_rails_4cbddb1981 FOREIGN KEY (target_uuid) REFERENCES public.knowledge_items(uuid) ON DELETE SET NULL;


--
-- Name: topic_memberships fk_rails_50149efe6b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_memberships
    ADD CONSTRAINT fk_rails_50149efe6b FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: tasks fk_rails_538e121d51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_538e121d51 FOREIGN KEY (parent_id) REFERENCES public.tasks(id);


--
-- Name: work_nodes fk_rails_560da82e40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes
    ADD CONSTRAINT fk_rails_560da82e40 FOREIGN KEY (tree_id) REFERENCES public.topic_trees(id);


--
-- Name: events fk_rails_574786ddb2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_574786ddb2 FOREIGN KEY (communication_id) REFERENCES public.communications(id);


--
-- Name: tasks fk_rails_59871d16cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_59871d16cb FOREIGN KEY (inbox_item_id) REFERENCES public.inbox_items(id);


--
-- Name: knowledge_item_topics fk_rails_5aef9c382d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_topics
    ADD CONSTRAINT fk_rails_5aef9c382d FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: work_nodes fk_rails_5bdb7ce4a3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes
    ADD CONSTRAINT fk_rails_5bdb7ce4a3 FOREIGN KEY (parent_id) REFERENCES public.work_nodes(id) ON DELETE CASCADE;


--
-- Name: awaitings fk_rails_5ff65c2139; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaitings
    ADD CONSTRAINT fk_rails_5ff65c2139 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: topic_trees fk_rails_60e86080e6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_trees
    ADD CONSTRAINT fk_rails_60e86080e6 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: inbox_item_topics fk_rails_64636f2469; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item_topics
    ADD CONSTRAINT fk_rails_64636f2469 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: task_topics fk_rails_64bbad2577; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_topics
    ADD CONSTRAINT fk_rails_64bbad2577 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: topics fk_rails_685fe8bf50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT fk_rails_685fe8bf50 FOREIGN KEY (parent_topic_id) REFERENCES public.topics(id);


--
-- Name: tasks fk_rails_6aa22755b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_6aa22755b3 FOREIGN KEY (communication_id) REFERENCES public.communications(id);


--
-- Name: knowledge_item_topics fk_rails_6c0c16c97d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_topics
    ADD CONSTRAINT fk_rails_6c0c16c97d FOREIGN KEY (knowledge_item_uuid) REFERENCES public.knowledge_items(uuid);


--
-- Name: document_fields fk_rails_6dd107ce03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_fields
    ADD CONSTRAINT fk_rails_6dd107ce03 FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: wikilink_research_jobs fk_rails_7655bf4370; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wikilink_research_jobs
    ADD CONSTRAINT fk_rails_7655bf4370 FOREIGN KEY (target_knowledge_item_id) REFERENCES public.knowledge_items(uuid);


--
-- Name: topics fk_rails_798926876b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT fk_rails_798926876b FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: task_dependencies fk_rails_7f4efd230e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_dependencies
    ADD CONSTRAINT fk_rails_7f4efd230e FOREIGN KEY (successor_id) REFERENCES public.tasks(id);


--
-- Name: task_anchors fk_rails_8064498e59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_anchors
    ADD CONSTRAINT fk_rails_8064498e59 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: oauth_credentials fk_rails_8394ad1d52; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_credentials
    ADD CONSTRAINT fk_rails_8394ad1d52 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: source_topics fk_rails_83fc71f0d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_topics
    ADD CONSTRAINT fk_rails_83fc71f0d8 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: awaitings fk_rails_860ac727a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaitings
    ADD CONSTRAINT fk_rails_860ac727a1 FOREIGN KEY (communication_id) REFERENCES public.communications(id);


--
-- Name: source_identifiers fk_rails_89c8560796; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_identifiers
    ADD CONSTRAINT fk_rails_89c8560796 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: task_topics fk_rails_8a6bf8bd52; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_topics
    ADD CONSTRAINT fk_rails_8a6bf8bd52 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: capabilities fk_rails_8a8433996e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities
    ADD CONSTRAINT fk_rails_8a8433996e FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: actor_views fk_rails_8b8f44ec8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_views
    ADD CONSTRAINT fk_rails_8b8f44ec8f FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: time_entries fk_rails_9324bf7672; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_9324bf7672 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: time_segments fk_rails_971b5eb1d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_segments
    ADD CONSTRAINT fk_rails_971b5eb1d0 FOREIGN KEY (time_entry_id) REFERENCES public.time_entries(id);


--
-- Name: inbox_item_topics fk_rails_99e85481a5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item_topics
    ADD CONSTRAINT fk_rails_99e85481a5 FOREIGN KEY (inbox_item_id) REFERENCES public.inbox_items(id);


--
-- Name: work_nodes fk_rails_9f6a294ec3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes
    ADD CONSTRAINT fk_rails_9f6a294ec3 FOREIGN KEY (knowledge_item_uuid) REFERENCES public.knowledge_items(uuid) ON DELETE RESTRICT;


--
-- Name: taggings fk_rails_9fcd2e236b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT fk_rails_9fcd2e236b FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: wikilink_research_jobs fk_rails_9fe8f83a8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wikilink_research_jobs
    ADD CONSTRAINT fk_rails_9fe8f83a8f FOREIGN KEY (source_knowledge_item_id) REFERENCES public.knowledge_items(uuid);


--
-- Name: comment_reads fk_rails_a3fc52cf1e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reads
    ADD CONSTRAINT fk_rails_a3fc52cf1e FOREIGN KEY (actor_id) REFERENCES public.actors(id) ON DELETE CASCADE;


--
-- Name: communication_topics fk_rails_a6e8721029; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_topics
    ADD CONSTRAINT fk_rails_a6e8721029 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: knowledge_item_pins fk_rails_a83d53bc72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_item_pins
    ADD CONSTRAINT fk_rails_a83d53bc72 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: knowledge_items fk_rails_a96ffbef31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_items
    ADD CONSTRAINT fk_rails_a96ffbef31 FOREIGN KEY (inbox_item_id) REFERENCES public.inbox_items(id);


--
-- Name: awaiting_topics fk_rails_a9cedfca3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaiting_topics
    ADD CONSTRAINT fk_rails_a9cedfca3b FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: task_sources fk_rails_b86340038e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_sources
    ADD CONSTRAINT fk_rails_b86340038e FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: task_attachments fk_rails_c300ac3231; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT fk_rails_c300ac3231 FOREIGN KEY (uploader_id) REFERENCES public.actors(id);


--
-- Name: task_comments fk_rails_c66c8b237a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT fk_rails_c66c8b237a FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: topic_memberships fk_rails_c935390edf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topic_memberships
    ADD CONSTRAINT fk_rails_c935390edf FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: time_entries fk_rails_c93cd89c62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT fk_rails_c93cd89c62 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: invoice_lines fk_rails_ce99ddfc5f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_lines
    ADD CONSTRAINT fk_rails_ce99ddfc5f FOREIGN KEY (document_id) REFERENCES public.documents(id);


--
-- Name: source_topics fk_rails_cec8862d72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.source_topics
    ADD CONSTRAINT fk_rails_cec8862d72 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: work_nodes fk_rails_d82ebb479f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_nodes
    ADD CONSTRAINT fk_rails_d82ebb479f FOREIGN KEY (topic_id) REFERENCES public.topics(id) ON DELETE CASCADE;


--
-- Name: portal_accesses fk_rails_d83fa1c1c5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_accesses
    ADD CONSTRAINT fk_rails_d83fa1c1c5 FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: knowledge_items fk_rails_dd7d29995f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_items
    ADD CONSTRAINT fk_rails_dd7d29995f FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: actor_mentions fk_rails_e293ecacbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actor_mentions
    ADD CONSTRAINT fk_rails_e293ecacbf FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: communications fk_rails_e3ae9adf19; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communications
    ADD CONSTRAINT fk_rails_e3ae9adf19 FOREIGN KEY (oauth_credential_id) REFERENCES public.oauth_credentials(id);


--
-- Name: topics fk_rails_e3bc089387; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topics
    ADD CONSTRAINT fk_rails_e3bc089387 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: comment_reads fk_rails_e44626aa0f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reads
    ADD CONSTRAINT fk_rails_e44626aa0f FOREIGN KEY (task_comment_id) REFERENCES public.task_comments(id) ON DELETE CASCADE;


--
-- Name: inbox_items fk_rails_e5accd4cd6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_items
    ADD CONSTRAINT fk_rails_e5accd4cd6 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- Name: events fk_rails_e5e78194cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_e5e78194cb FOREIGN KEY (topic_id) REFERENCES public.topics(id);


--
-- Name: capabilities fk_rails_ea8e64791a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capabilities
    ADD CONSTRAINT fk_rails_ea8e64791a FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: task_attachments fk_rails_ebdf34eff6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT fk_rails_ebdf34eff6 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: llm_activities fk_rails_ecc2899b91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.llm_activities
    ADD CONSTRAINT fk_rails_ecc2899b91 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: task_sources fk_rails_f187a48030; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_sources
    ADD CONSTRAINT fk_rails_f187a48030 FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: awaiting_topics fk_rails_f5b5fc15ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.awaiting_topics
    ADD CONSTRAINT fk_rails_f5b5fc15ba FOREIGN KEY (awaiting_id) REFERENCES public.awaitings(id);


--
-- Name: task_templates fk_rails_fb3a1bf198; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_templates
    ADD CONSTRAINT fk_rails_fb3a1bf198 FOREIGN KEY (agent_actor_id) REFERENCES public.actors(id) ON DELETE SET NULL;


--
-- Name: sources fk_rails_feff9c4680; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT fk_rails_feff9c4680 FOREIGN KEY (creator_id) REFERENCES public.actors(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260702170000'),
('20260629230000'),
('20260629220000'),
('20260629210000'),
('20260623130000'),
('20260623120000'),
('20260618120000'),
('20260615130000'),
('20260615120000'),
('20260614160000'),
('20260614140000'),
('20260612090000'),
('20260611150000'),
('20260611120000'),
('20260610200501'),
('20260610165120'),
('20260610124620'),
('20260610015344'),
('20260610013335'),
('20260610011641'),
('20260609214122'),
('20260608220000'),
('20260608210500'),
('20260608210000'),
('20260608200000'),
('20260608180500'),
('20260608180000'),
('20260608170000'),
('20260608160500'),
('20260608160000'),
('20260608140000'),
('20260608120000'),
('20260607150000'),
('20260607140000'),
('20260607010000'),
('20260607000001'),
('20260605100000'),
('20260605090000'),
('20260604130000'),
('20260603120000'),
('20260602211500'),
('20260602210000'),
('20260531215735'),
('20260531141653'),
('20260530191138'),
('20260528172500'),
('20260528172000'),
('20260527200649'),
('20260527185311'),
('20260527175827'),
('20260527145539'),
('20260525120000'),
('20260524210000'),
('20260523220500'),
('20260523220000'),
('20260521110000'),
('20260520230000'),
('20260520100000'),
('20260519230000'),
('20260519220000'),
('20260519164000'),
('20260519163000'),
('20260519140000'),
('20260519114000'),
('20260519082500'),
('20260518160000'),
('20260515110000'),
('20260513120100'),
('20260513120000'),
('20260513110000'),
('20260513100000'),
('20260513090000'),
('20260513010000'),
('20260512140000'),
('20260512110000'),
('20260512100000'),
('20260511060000'),
('20260510210000'),
('20260510180000'),
('20260510170100'),
('20260510170000'),
('20260510081517'),
('20260510072951'),
('20260510072612'),
('20260510072559'),
('20260509210000'),
('20260509180001'),
('20260509120001'),
('20260508120001'),
('20260503130004'),
('20260503130003'),
('20260503130002'),
('20260503130001'),
('20260503120003'),
('20260503120002'),
('20260503120001'),
('20260503110001'),
('20260503100001'),
('20260502130001'),
('20260502120002'),
('20260502120001'),
('20260502110001'),
('20260502100001'),
('20260501110001'),
('20260501100001'),
('20260427110001'),
('20260427100001'),
('20260426110001'),
('20260426100001'),
('20260425100001'),
('20260421140001'),
('20260421120001'),
('20260421100001'),
('20260421080001'),
('20260420210001'),
('20260420200003'),
('20260420200002'),
('20260420200001'),
('20260420180002'),
('20260420180001'),
('20260419170001'),
('20260419150001'),
('20260419140005'),
('20260419140004'),
('20260419140003'),
('20260419140002'),
('20260419140001'),
('20260419130004'),
('20260419130003'),
('20260419130002'),
('20260419130001'),
('20260419120011'),
('20260419120010'),
('20260419120009'),
('20260419120008'),
('20260419120007'),
('20260419120006'),
('20260419120005'),
('20260419120004'),
('20260419120003'),
('20260419120002'),
('20260419120001');


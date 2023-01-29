--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1 (Debian 15.1-1.pgdg110+1)
-- Dumped by pg_dump version 15.0 (Homebrew)

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
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: calendar_view; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.calendar_view AS ENUM (
    'day',
    'week',
    'all'
);


--
-- Name: repository_user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.repository_user_role AS ENUM (
    'owner',
    'admin',
    'write',
    'read'
);


--
-- Name: json_object_delete_keys(json, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.json_object_delete_keys(json json, VARIADIC keys_to_delete text[]) RETURNS json
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT COALESCE(
  (SELECT ('{' || string_agg(to_json("key") || ':' || "value", ',') || '}')
   FROM json_each("json")
   WHERE "key" <> ALL ("keys_to_delete")),
  '{}'
)::json
$$;


--
-- Name: json_object_set_key(json, text, anyelement); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.json_object_set_key(json json, key_to_set text, value_to_set anyelement) RETURNS json
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')::json
  FROM (SELECT *
          FROM json_each("json")
         WHERE "key" <> "key_to_set"
         UNION ALL
        SELECT "key_to_set", to_json("value_to_set")) AS "fields"
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id bigint,
    action character varying(255) NOT NULL,
    params jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    user_agent character varying(255),
    organization_id bigint,
    remote_ip character varying(255)
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
-- Name: blocked_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocked_addresses (
    id integer NOT NULL,
    ip text NOT NULL,
    comment text
);


--
-- Name: blocked_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blocked_addresses_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blocked_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blocked_addresses_id_seq OWNED BY public.blocked_addresses.id;


--
-- Name: downloads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.downloads (
    id integer NOT NULL,
    release_id integer NOT NULL,
    downloads integer NOT NULL,
    day date NOT NULL,
    package_id bigint NOT NULL
);


--
-- Name: downloads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.downloads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: downloads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.downloads_id_seq OWNED BY public.downloads.id;


--
-- Name: emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emails (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    verified boolean NOT NULL,
    "primary" boolean NOT NULL,
    public boolean NOT NULL,
    verification_key character varying(255),
    user_id integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    gravatar boolean DEFAULT false NOT NULL,
    verification_expiry timestamp without time zone
);


--
-- Name: emails_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.emails_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.emails_id_seq OWNED BY public.emails.id;


--
-- Name: installs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.installs (
    id integer NOT NULL,
    hex text NOT NULL,
    elixirs text[] NOT NULL
);


--
-- Name: installs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.installs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: installs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.installs_id_seq OWNED BY public.installs.id;


--
-- Name: keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.keys (
    id integer NOT NULL,
    user_id integer,
    name text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    secret_first text NOT NULL,
    secret_second text NOT NULL,
    revoked_at timestamp without time zone,
    permissions jsonb[] NOT NULL,
    last_use jsonb,
    organization_id bigint,
    public boolean DEFAULT true NOT NULL,
    revoke_at timestamp without time zone
);


--
-- Name: keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.keys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.keys_id_seq OWNED BY public.keys.id;


--
-- Name: organization_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_users (
    id bigint NOT NULL,
    role public.repository_user_role NOT NULL,
    organization_id bigint NOT NULL,
    user_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    public boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    billing_active boolean DEFAULT false NOT NULL,
    trial_end timestamp without time zone NOT NULL
);


--
-- Name: packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.packages (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    meta jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    docs_updated_at timestamp without time zone,
    repository_id integer NOT NULL
);


--
-- Name: releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.releases (
    id integer NOT NULL,
    package_id integer NOT NULL,
    version text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    has_docs boolean DEFAULT false NOT NULL,
    meta jsonb NOT NULL,
    retirement jsonb,
    publisher_id bigint,
    inner_checksum bytea NOT NULL,
    outer_checksum bytea
);


--
-- Name: repositories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repositories (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    organization_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requirements (
    id integer NOT NULL,
    release_id integer NOT NULL,
    dependency_id integer NOT NULL,
    requirement text NOT NULL,
    optional boolean DEFAULT false NOT NULL,
    app text NOT NULL
);


--
-- Name: package_dependants; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.package_dependants AS
 SELECT DISTINCT p3.name,
    r4.name AS repo,
    p0.id AS dependant_id
   FROM ((((public.packages p0
     JOIN public.releases r1 ON ((r1.package_id = p0.id)))
     JOIN public.requirements r2 ON ((r2.release_id = r1.id)))
     JOIN public.packages p3 ON ((p3.id = r2.dependency_id)))
     JOIN public.repositories r4 ON ((r4.id = p3.repository_id)))
  WITH NO DATA;


--
-- Name: package_downloads; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.package_downloads AS
 SELECT r.package_id,
    v.view,
    sum(d.downloads) AS downloads
   FROM ((public.downloads d
     JOIN public.releases r ON ((r.id = d.release_id)))
     CROSS JOIN ( VALUES ('day'::text), ('week'::text), ('recent'::text), ('all'::text)) v(view))
  WHERE
        CASE
            WHEN (v.view = 'day'::text) THEN (d.day = (CURRENT_DATE - '1 day'::interval))
            WHEN (v.view = 'week'::text) THEN ((d.day >= (CURRENT_DATE - '7 days'::interval)) AND (d.day <= (CURRENT_DATE - '1 day'::interval)))
            WHEN (v.view = 'recent'::text) THEN ((d.day >= (CURRENT_DATE - '90 days'::interval)) AND (d.day <= (CURRENT_DATE - '1 day'::interval)))
            WHEN (v.view = 'all'::text) THEN true
            ELSE NULL::boolean
        END
  GROUP BY r.package_id, v.view
UNION
 SELECT NULL::integer AS package_id,
    'day'::text AS view,
    sum(d.downloads) AS downloads
   FROM public.downloads d
  WHERE (d.day = (CURRENT_DATE - '1 day'::interval))
UNION
 SELECT NULL::integer AS package_id,
    'week'::text AS view,
    sum(d.downloads) AS downloads
   FROM public.downloads d
  WHERE ((d.day >= (CURRENT_DATE - '7 days'::interval)) AND (d.day <= (CURRENT_DATE - '1 day'::interval)))
UNION
 SELECT NULL::integer AS package_id,
    'recent'::text AS view,
    sum(d.downloads) AS downloads
   FROM public.downloads d
  WHERE ((d.day >= (CURRENT_DATE - '90 days'::interval)) AND (d.day <= (CURRENT_DATE - '1 day'::interval)))
UNION
 SELECT NULL::integer AS package_id,
    'all'::text AS view,
    sum(d.downloads) AS downloads
   FROM public.downloads d
  WITH NO DATA;


--
-- Name: package_owners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_owners (
    id integer NOT NULL,
    package_id integer NOT NULL,
    user_id integer NOT NULL,
    level character varying(255) DEFAULT 'full'::character varying NOT NULL,
    inserted_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: package_owners_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.package_owners_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: package_owners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.package_owners_id_seq OWNED BY public.package_owners.id;


--
-- Name: package_report_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_report_comments (
    id bigint NOT NULL,
    text text NOT NULL,
    author_id bigint NOT NULL,
    package_report_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: package_report_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.package_report_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: package_report_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.package_report_comments_id_seq OWNED BY public.package_report_comments.id;


--
-- Name: package_report_releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_report_releases (
    id bigint NOT NULL,
    package_report_id bigint NOT NULL,
    release_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: package_report_releases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.package_report_releases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: package_report_releases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.package_report_releases_id_seq OWNED BY public.package_report_releases.id;


--
-- Name: package_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.package_reports (
    id bigint NOT NULL,
    description text NOT NULL,
    state character varying(255) NOT NULL,
    package_id bigint NOT NULL,
    author_id bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: package_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.package_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: package_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.package_reports_id_seq OWNED BY public.package_reports.id;


--
-- Name: packages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.packages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: packages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.packages_id_seq OWNED BY public.packages.id;


--
-- Name: password_resets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_resets (
    id bigint NOT NULL,
    key character varying(255) NOT NULL,
    primary_email character varying(255) NOT NULL,
    user_id bigint,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: password_resets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.password_resets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: password_resets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.password_resets_id_seq OWNED BY public.password_resets.id;


--
-- Name: release_downloads; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.release_downloads AS
 SELECT downloads.package_id,
    downloads.release_id,
    sum(downloads.downloads) AS downloads
   FROM public.downloads
  GROUP BY downloads.package_id, downloads.release_id
  WITH NO DATA;


--
-- Name: releases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.releases_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: releases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.releases_id_seq OWNED BY public.releases.id;


--
-- Name: repositories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.repositories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: repositories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.repositories_id_seq OWNED BY public.organizations.id;


--
-- Name: repositories_id_seq1; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.repositories_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: repositories_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.repositories_id_seq1 OWNED BY public.repositories.id;


--
-- Name: repository_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.repository_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: repository_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.repository_users_id_seq OWNED BY public.organization_users.id;


--
-- Name: requirements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.requirements_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: requirements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.requirements_id_seq OWNED BY public.requirements.id;


--
-- Name: reserved_packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserved_packages (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    version character varying(255),
    reason character varying(255),
    repository_id integer NOT NULL
);


--
-- Name: reserved_packages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reserved_packages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reserved_packages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reserved_packages_id_seq OWNED BY public.reserved_packages.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    token bytea NOT NULL,
    data jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: short_urls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.short_urls (
    id bigint NOT NULL,
    url text NOT NULL,
    short_code character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: short_urls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.short_urls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: short_urls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.short_urls_id_seq OWNED BY public.short_urls.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username public.citext NOT NULL,
    password text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    full_name text,
    handles jsonb DEFAULT (json_build_object('id', (public.uuid_generate_v4())::text))::jsonb,
    service boolean DEFAULT false,
    organization_id bigint,
    deactivated_at timestamp(0) without time zone,
    tfa jsonb,
    role character varying(255) DEFAULT 'basic'::character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: blocked_addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_addresses ALTER COLUMN id SET DEFAULT nextval('public.blocked_addresses_id_seq'::regclass);


--
-- Name: downloads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downloads ALTER COLUMN id SET DEFAULT nextval('public.downloads_id_seq'::regclass);


--
-- Name: emails id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails ALTER COLUMN id SET DEFAULT nextval('public.emails_id_seq'::regclass);


--
-- Name: installs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installs ALTER COLUMN id SET DEFAULT nextval('public.installs_id_seq'::regclass);


--
-- Name: keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys ALTER COLUMN id SET DEFAULT nextval('public.keys_id_seq'::regclass);


--
-- Name: organization_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_users ALTER COLUMN id SET DEFAULT nextval('public.repository_users_id_seq'::regclass);


--
-- Name: organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations ALTER COLUMN id SET DEFAULT nextval('public.repositories_id_seq'::regclass);


--
-- Name: package_owners id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_owners ALTER COLUMN id SET DEFAULT nextval('public.package_owners_id_seq'::regclass);


--
-- Name: package_report_comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_comments ALTER COLUMN id SET DEFAULT nextval('public.package_report_comments_id_seq'::regclass);


--
-- Name: package_report_releases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_releases ALTER COLUMN id SET DEFAULT nextval('public.package_report_releases_id_seq'::regclass);


--
-- Name: package_reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_reports ALTER COLUMN id SET DEFAULT nextval('public.package_reports_id_seq'::regclass);


--
-- Name: packages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.packages ALTER COLUMN id SET DEFAULT nextval('public.packages_id_seq'::regclass);


--
-- Name: password_resets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_resets ALTER COLUMN id SET DEFAULT nextval('public.password_resets_id_seq'::regclass);


--
-- Name: releases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases ALTER COLUMN id SET DEFAULT nextval('public.releases_id_seq'::regclass);


--
-- Name: repositories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repositories ALTER COLUMN id SET DEFAULT nextval('public.repositories_id_seq1'::regclass);


--
-- Name: requirements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements ALTER COLUMN id SET DEFAULT nextval('public.requirements_id_seq'::regclass);


--
-- Name: reserved_packages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserved_packages ALTER COLUMN id SET DEFAULT nextval('public.reserved_packages_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: short_urls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_urls ALTER COLUMN id SET DEFAULT nextval('public.short_urls_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: blocked_addresses blocked_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_addresses
    ADD CONSTRAINT blocked_addresses_pkey PRIMARY KEY (id);


--
-- Name: downloads downloads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downloads
    ADD CONSTRAINT downloads_pkey PRIMARY KEY (id);


--
-- Name: emails emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_pkey PRIMARY KEY (id);


--
-- Name: installs installs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.installs
    ADD CONSTRAINT installs_pkey PRIMARY KEY (id);


--
-- Name: keys keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_pkey PRIMARY KEY (id);


--
-- Name: keys keys_secret_first_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_secret_first_key UNIQUE (secret_first);


--
-- Name: organization_users organization_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_users
    ADD CONSTRAINT organization_users_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: package_owners package_owners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_owners
    ADD CONSTRAINT package_owners_pkey PRIMARY KEY (id);


--
-- Name: package_owners package_owners_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_owners
    ADD CONSTRAINT package_owners_unique UNIQUE (package_id, user_id);


--
-- Name: package_report_comments package_report_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_comments
    ADD CONSTRAINT package_report_comments_pkey PRIMARY KEY (id);


--
-- Name: package_report_releases package_report_releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_releases
    ADD CONSTRAINT package_report_releases_pkey PRIMARY KEY (id);


--
-- Name: package_reports package_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_reports
    ADD CONSTRAINT package_reports_pkey PRIMARY KEY (id);


--
-- Name: packages packages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.packages
    ADD CONSTRAINT packages_pkey PRIMARY KEY (id);


--
-- Name: password_resets password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- Name: releases releases_package_id_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_package_id_version_key UNIQUE (package_id, version);


--
-- Name: releases releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_pkey PRIMARY KEY (id);


--
-- Name: repositories repositories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repositories
    ADD CONSTRAINT repositories_pkey PRIMARY KEY (id);


--
-- Name: requirements requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements
    ADD CONSTRAINT requirements_pkey PRIMARY KEY (id);


--
-- Name: reserved_packages reserved_packages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserved_packages
    ADD CONSTRAINT reserved_packages_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: short_urls short_urls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.short_urls
    ADD CONSTRAINT short_urls_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: audit_logs_actor_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_actor_id_index ON public.audit_logs USING btree (user_id);


--
-- Name: audit_logs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_inserted_at_index ON public.audit_logs USING btree (inserted_at);


--
-- Name: audit_logs_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_organization_id_index ON public.audit_logs USING btree (organization_id);


--
-- Name: audit_logs_params_package_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_params_package_id_index ON public.audit_logs USING btree (((((params -> 'package'::text) ->> 'id'::text))::integer));


--
-- Name: blocked_addresses_ip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX blocked_addresses_ip_idx ON public.blocked_addresses USING btree (ip);


--
-- Name: downloads_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downloads_day_idx ON public.downloads USING btree (day);


--
-- Name: downloads_package_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downloads_package_id_index ON public.downloads USING btree (package_id);


--
-- Name: downloads_release_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downloads_release_id_idx ON public.downloads USING btree (release_id);


--
-- Name: emails_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX emails_email_key ON public.emails USING btree (email) WHERE (verified = true);


--
-- Name: emails_email_user_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX emails_email_user_key ON public.emails USING btree (email, user_id);


--
-- Name: emails_user_id_case_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX emails_user_id_case_idx ON public.emails USING btree (user_id, (
CASE
    WHEN "primary" THEN true
    ELSE NULL::boolean
END));


--
-- Name: emails_user_id_case_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX emails_user_id_case_idx1 ON public.emails USING btree (user_id, (
CASE
    WHEN public THEN true
    ELSE NULL::boolean
END));


--
-- Name: installs_hex_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX installs_hex_index ON public.installs USING btree (hex);


--
-- Name: keys_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX keys_name_index ON public.keys USING btree (name);


--
-- Name: keys_organization_id_name_revoked_at_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX keys_organization_id_name_revoked_at_key ON public.keys USING btree (organization_id, name) WHERE (revoked_at IS NULL);


--
-- Name: keys_revoke_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX keys_revoke_at_index ON public.keys USING btree (revoke_at);


--
-- Name: keys_revoked_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX keys_revoked_at_index ON public.keys USING btree (revoked_at);


--
-- Name: keys_user_id_name_revoked_at_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX keys_user_id_name_revoked_at_key ON public.keys USING btree (user_id, name) WHERE (revoked_at IS NULL);


--
-- Name: organization_users_organization_id_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organization_users_organization_id_user_id_index ON public.organization_users USING btree (organization_id, user_id);


--
-- Name: organization_users_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_users_user_id_index ON public.organization_users USING btree (user_id);


--
-- Name: organizations_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organizations_name_index ON public.organizations USING btree (name);


--
-- Name: organizations_public_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organizations_public_index ON public.organizations USING btree (public);


--
-- Name: package_dependants_name_repo_dependant_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX package_dependants_name_repo_dependant_id_idx ON public.package_dependants USING btree (name, repo, dependant_id);


--
-- Name: package_downloads_downloads_DESC_NULLS_LAST_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "package_downloads_downloads_DESC_NULLS_LAST_index" ON public.package_downloads USING btree (downloads DESC NULLS LAST);


--
-- Name: package_downloads_package_id_view_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX package_downloads_package_id_view_idx ON public.package_downloads USING btree (package_id, view);


--
-- Name: package_downloads_view_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_downloads_view_index ON public.package_downloads USING btree (view);


--
-- Name: package_owners_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_owners_user_id_index ON public.package_owners USING btree (user_id);


--
-- Name: package_report_comments_package_report_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_report_comments_package_report_id_index ON public.package_report_comments USING btree (package_report_id);


--
-- Name: package_report_releases_package_report_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_report_releases_package_report_id_index ON public.package_report_releases USING btree (package_report_id);


--
-- Name: package_report_releases_release_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_report_releases_release_id_index ON public.package_report_releases USING btree (release_id);


--
-- Name: package_reports_package_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX package_reports_package_id_index ON public.package_reports USING btree (package_id);


--
-- Name: packages_description_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_description_text ON public.packages USING gin (to_tsvector('english'::regconfig, regexp_replace(((meta -> 'description'::text))::text, '/'::text, ' '::text)));


--
-- Name: packages_inserted_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_inserted_at_idx ON public.packages USING btree (inserted_at);


--
-- Name: packages_meta_extra_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_meta_extra_idx ON public.packages USING gin (((meta -> 'extra'::text)) jsonb_path_ops);


--
-- Name: packages_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_name_index ON public.packages USING btree (name);


--
-- Name: packages_name_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_name_trgm ON public.packages USING gin (name public.gin_trgm_ops);


--
-- Name: packages_repository_id_name_text_pattern_ops_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX packages_repository_id_name_text_pattern_ops_index ON public.packages USING btree (repository_id, name text_pattern_ops);


--
-- Name: packages_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX packages_updated_at_idx ON public.packages USING btree (updated_at);


--
-- Name: password_resets_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX password_resets_user_id_index ON public.password_resets USING btree (user_id);


--
-- Name: release_downloads_release_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX release_downloads_release_id_idx ON public.release_downloads USING btree (release_id);


--
-- Name: releases_inserted_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX releases_inserted_at_idx ON public.releases USING btree (inserted_at);


--
-- Name: releases_package_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX releases_package_id_idx ON public.releases USING btree (package_id);


--
-- Name: repositories_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX repositories_name_index ON public.repositories USING btree (name);


--
-- Name: repositories_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX repositories_organization_id_index ON public.repositories USING btree (organization_id);


--
-- Name: requirements_release_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requirements_release_id_idx ON public.requirements USING btree (release_id);


--
-- Name: reserved_packages_repository_id_name_version_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reserved_packages_repository_id_name_version_index ON public.reserved_packages USING btree (repository_id, name, version);


--
-- Name: short_urls_short_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX short_urls_short_code_index ON public.short_urls USING btree (short_code);


--
-- Name: users_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_organization_id_index ON public.users USING btree (organization_id);


--
-- Name: users_username_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_username_idx ON public.users USING btree (username);


--
-- Name: audit_logs audit_logs_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: audit_logs audit_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: downloads downloads_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downloads
    ADD CONSTRAINT downloads_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.packages(id) ON DELETE CASCADE;


--
-- Name: downloads downloads_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downloads
    ADD CONSTRAINT downloads_release_id_fkey FOREIGN KEY (release_id) REFERENCES public.releases(id) ON DELETE CASCADE;


--
-- Name: emails emails_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emails
    ADD CONSTRAINT emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: keys keys_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: keys keys_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: organization_users organization_users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_users
    ADD CONSTRAINT organization_users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: organization_users organization_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_users
    ADD CONSTRAINT organization_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: package_owners package_owners_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_owners
    ADD CONSTRAINT package_owners_owner_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: package_owners package_owners_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_owners
    ADD CONSTRAINT package_owners_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.packages(id) ON DELETE CASCADE;


--
-- Name: package_report_comments package_report_comments_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_comments
    ADD CONSTRAINT package_report_comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: package_report_comments package_report_comments_package_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_comments
    ADD CONSTRAINT package_report_comments_package_report_id_fkey FOREIGN KEY (package_report_id) REFERENCES public.package_reports(id);


--
-- Name: package_report_releases package_report_releases_package_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_releases
    ADD CONSTRAINT package_report_releases_package_report_id_fkey FOREIGN KEY (package_report_id) REFERENCES public.package_reports(id);


--
-- Name: package_report_releases package_report_releases_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_report_releases
    ADD CONSTRAINT package_report_releases_release_id_fkey FOREIGN KEY (release_id) REFERENCES public.releases(id);


--
-- Name: package_reports package_reports_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_reports
    ADD CONSTRAINT package_reports_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: package_reports package_reports_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.package_reports
    ADD CONSTRAINT package_reports_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.packages(id);


--
-- Name: packages packages_repository_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.packages
    ADD CONSTRAINT packages_repository_id_fkey FOREIGN KEY (repository_id) REFERENCES public.repositories(id);


--
-- Name: password_resets password_resets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: releases releases_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_package_id_fkey FOREIGN KEY (package_id) REFERENCES public.packages(id) ON DELETE RESTRICT;


--
-- Name: releases releases_publisher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_publisher_id_fkey FOREIGN KEY (publisher_id) REFERENCES public.users(id);


--
-- Name: repositories repositories_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repositories
    ADD CONSTRAINT repositories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: requirements requirements_dependency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements
    ADD CONSTRAINT requirements_dependency_id_fkey FOREIGN KEY (dependency_id) REFERENCES public.packages(id) ON DELETE RESTRICT;


--
-- Name: requirements requirements_release_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requirements
    ADD CONSTRAINT requirements_release_id_fkey FOREIGN KEY (release_id) REFERENCES public.releases(id) ON DELETE CASCADE;


--
-- Name: reserved_packages reserved_packages_repository_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserved_packages
    ADD CONSTRAINT reserved_packages_repository_id_fkey FOREIGN KEY (repository_id) REFERENCES public.repositories(id);


--
-- Name: users users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20140128201839);
INSERT INTO public."schema_migrations" (version) VALUES (20140128205233);
INSERT INTO public."schema_migrations" (version) VALUES (20140128213400);
INSERT INTO public."schema_migrations" (version) VALUES (20140128213543);
INSERT INTO public."schema_migrations" (version) VALUES (20140220143758);
INSERT INTO public."schema_migrations" (version) VALUES (20140316111040);
INSERT INTO public."schema_migrations" (version) VALUES (20140320212302);
INSERT INTO public."schema_migrations" (version) VALUES (20140323211856);
INSERT INTO public."schema_migrations" (version) VALUES (20140323232653);
INSERT INTO public."schema_migrations" (version) VALUES (20140510114425);
INSERT INTO public."schema_migrations" (version) VALUES (20140511133315);
INSERT INTO public."schema_migrations" (version) VALUES (20140518153329);
INSERT INTO public."schema_migrations" (version) VALUES (20140527204944);
INSERT INTO public."schema_migrations" (version) VALUES (20140606173220);
INSERT INTO public."schema_migrations" (version) VALUES (20140623215331);
INSERT INTO public."schema_migrations" (version) VALUES (20140819195307);
INSERT INTO public."schema_migrations" (version) VALUES (20140916081808);
INSERT INTO public."schema_migrations" (version) VALUES (20140919111541);
INSERT INTO public."schema_migrations" (version) VALUES (20141006184930);
INSERT INTO public."schema_migrations" (version) VALUES (20141008200254);
INSERT INTO public."schema_migrations" (version) VALUES (20141009190735);
INSERT INTO public."schema_migrations" (version) VALUES (20141011150402);
INSERT INTO public."schema_migrations" (version) VALUES (20141030030723);
INSERT INTO public."schema_migrations" (version) VALUES (20150117064046);
INSERT INTO public."schema_migrations" (version) VALUES (20150318235407);
INSERT INTO public."schema_migrations" (version) VALUES (20150409134413);
INSERT INTO public."schema_migrations" (version) VALUES (20150412185310);
INSERT INTO public."schema_migrations" (version) VALUES (20150428053201);
INSERT INTO public."schema_migrations" (version) VALUES (20150428072308);
INSERT INTO public."schema_migrations" (version) VALUES (20150428073015);
INSERT INTO public."schema_migrations" (version) VALUES (20150806212017);
INSERT INTO public."schema_migrations" (version) VALUES (20151123193006);
INSERT INTO public."schema_migrations" (version) VALUES (20151211222543);
INSERT INTO public."schema_migrations" (version) VALUES (20160201230456);
INSERT INTO public."schema_migrations" (version) VALUES (20160215102451);
INSERT INTO public."schema_migrations" (version) VALUES (20160227170838);
INSERT INTO public."schema_migrations" (version) VALUES (20160302203848);
INSERT INTO public."schema_migrations" (version) VALUES (20160307185911);
INSERT INTO public."schema_migrations" (version) VALUES (20160317073758);
INSERT INTO public."schema_migrations" (version) VALUES (20160518163325);
INSERT INTO public."schema_migrations" (version) VALUES (20160530102429);
INSERT INTO public."schema_migrations" (version) VALUES (20160530111051);
INSERT INTO public."schema_migrations" (version) VALUES (20160601131257);
INSERT INTO public."schema_migrations" (version) VALUES (20160610143806);
INSERT INTO public."schema_migrations" (version) VALUES (20160707161837);
INSERT INTO public."schema_migrations" (version) VALUES (20160714145602);
INSERT INTO public."schema_migrations" (version) VALUES (20160720221809);
INSERT INTO public."schema_migrations" (version) VALUES (20160801161005);
INSERT INTO public."schema_migrations" (version) VALUES (20161004123829);
INSERT INTO public."schema_migrations" (version) VALUES (20161008234245);
INSERT INTO public."schema_migrations" (version) VALUES (20161011231213);
INSERT INTO public."schema_migrations" (version) VALUES (20161023210711);
INSERT INTO public."schema_migrations" (version) VALUES (20161030220220);
INSERT INTO public."schema_migrations" (version) VALUES (20161105184905);
INSERT INTO public."schema_migrations" (version) VALUES (20170308190933);
INSERT INTO public."schema_migrations" (version) VALUES (20170308191944);
INSERT INTO public."schema_migrations" (version) VALUES (20170429120741);
INSERT INTO public."schema_migrations" (version) VALUES (20170613205641);
INSERT INTO public."schema_migrations" (version) VALUES (20170702145540);
INSERT INTO public."schema_migrations" (version) VALUES (20170702153930);
INSERT INTO public."schema_migrations" (version) VALUES (20170702160756);
INSERT INTO public."schema_migrations" (version) VALUES (20170902072705);
INSERT INTO public."schema_migrations" (version) VALUES (20170909142545);
INSERT INTO public."schema_migrations" (version) VALUES (20171201141936);
INSERT INTO public."schema_migrations" (version) VALUES (20171203144157);
INSERT INTO public."schema_migrations" (version) VALUES (20180317114920);
INSERT INTO public."schema_migrations" (version) VALUES (20180513160026);
INSERT INTO public."schema_migrations" (version) VALUES (20180514125027);
INSERT INTO public."schema_migrations" (version) VALUES (20180527001017);
INSERT INTO public."schema_migrations" (version) VALUES (20180528192945);
INSERT INTO public."schema_migrations" (version) VALUES (20180609210018);
INSERT INTO public."schema_migrations" (version) VALUES (20180611130729);
INSERT INTO public."schema_migrations" (version) VALUES (20180612162132);
INSERT INTO public."schema_migrations" (version) VALUES (20180613212143);
INSERT INTO public."schema_migrations" (version) VALUES (20180615161612);
INSERT INTO public."schema_migrations" (version) VALUES (20180701174643);
INSERT INTO public."schema_migrations" (version) VALUES (20180704214746);
INSERT INTO public."schema_migrations" (version) VALUES (20180713192815);
INSERT INTO public."schema_migrations" (version) VALUES (20181011082425);
INSERT INTO public."schema_migrations" (version) VALUES (20181019154146);
INSERT INTO public."schema_migrations" (version) VALUES (20181129040911);
INSERT INTO public."schema_migrations" (version) VALUES (20190129165916);
INSERT INTO public."schema_migrations" (version) VALUES (20190208150347);
INSERT INTO public."schema_migrations" (version) VALUES (20190523204039);
INSERT INTO public."schema_migrations" (version) VALUES (20190618121721);
INSERT INTO public."schema_migrations" (version) VALUES (20190727112837);
INSERT INTO public."schema_migrations" (version) VALUES (20190727120736);
INSERT INTO public."schema_migrations" (version) VALUES (20190728180328);
INSERT INTO public."schema_migrations" (version) VALUES (20190917171521);
INSERT INTO public."schema_migrations" (version) VALUES (20190923222150);
INSERT INTO public."schema_migrations" (version) VALUES (20191119194728);
INSERT INTO public."schema_migrations" (version) VALUES (20200416050611);
INSERT INTO public."schema_migrations" (version) VALUES (20200605151334);
INSERT INTO public."schema_migrations" (version) VALUES (20200609095835);
INSERT INTO public."schema_migrations" (version) VALUES (20200612082909);
INSERT INTO public."schema_migrations" (version) VALUES (20200711092923);
INSERT INTO public."schema_migrations" (version) VALUES (20200718042121);
INSERT INTO public."schema_migrations" (version) VALUES (20200718045909);
INSERT INTO public."schema_migrations" (version) VALUES (20200718051728);
INSERT INTO public."schema_migrations" (version) VALUES (20211019235721);
INSERT INTO public."schema_migrations" (version) VALUES (20211102164710);
INSERT INTO public."schema_migrations" (version) VALUES (20220218173443);
INSERT INTO public."schema_migrations" (version) VALUES (20220218182929);
INSERT INTO public."schema_migrations" (version) VALUES (20220219012733);
INSERT INTO public."schema_migrations" (version) VALUES (20220219013427);
INSERT INTO public."schema_migrations" (version) VALUES (20220323140836);
INSERT INTO public."schema_migrations" (version) VALUES (20221103004202);
INSERT INTO public."schema_migrations" (version) VALUES (20221106173432);

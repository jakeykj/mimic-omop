WITH 
"proc_icd" as (SELECT mimic_id as procedure_occurrence_id, subject_id, hadm_id, icd9_code as procedure_source_value, CASE WHEN length(cast(ICD9_CODE as text)) = 2 THEN cast(ICD9_CODE as text) ELSE concat(substr(cast(ICD9_CODE as text), 1, 2), '.', substr(cast(ICD9_CODE as text), 3)) END AS concept_code FROM procedures_icd),
"local_proc_icd" AS (SELECT concept_id as procedure_source_concept_id, concept_code as procedure_source_value FROM omop.concept WHERE domain_id = 'Procedure' AND vocabulary_id = 'MIMIC ICD9Proc'),
"concept_proc_icd9" as ( SELECT concept_id as procedure_concept_id, concept_code FROM omop.concept WHERE vocabulary_id = 'ICD9Proc'),
"patients" AS (SELECT subject_id, mimic_id as person_id FROM patients),
"admissions" AS (SELECT hadm_id, admittime, dischtime as procedure_datetime, mimic_id as visit_occurrence_id FROM admissions),
"proc_event" as (SELECT d_items.mimic_id AS procedure_source_concept_id, procedureevents_mv.mimic_id as procedure_occurrence_id, subject_id, hadm_id, itemid, starttime as procedure_datetime, label as procedure_source_value FROM procedureevents_mv LEFT JOIN d_items USING (itemid)),
"gcpt_procedure_to_concept" as (SELECT item_id as itemid, concept_id as procedure_concept_id from gcpt_procedure_to_concept),
"concept_cpt4" AS (SELECT concept_id as procedure_concept_id, concept_code from omop.concept where vocabulary_id = 'CPT4'),
"cpt_event" AS ( SELECT mimic_id as procedure_occurrence_id , subject_id , hadm_id , chartdate as procedure_datetime , trim('[' || coalesce(costcenter,'') || '][' || coalesce(sectionheader,'') || '] ' || subsectionheader || ' ' || coalesce(description, '')) as procedure_source_value FROM cptevents),
"gcpt_cpt4_to_concept" as (SELECT * FROM gcpt_cpt4_to_concept),
"row_to_insert" AS (
SELECT
  procedure_occurrence_id
, patients.person_id
, coalesce(gcpt_cpt4_to_concept.procedure_concept_id,0) as procedure_concept_id
, coalesce(cpt_event.procedure_datetime, admissions.admittime)::date as procedure_date
, (coalesce(cpt_event.procedure_datetime, admissions.admittime)) as procedure_datetime
, 257 as procedure_type_concept_id -- Hospitalization Cost Record
, null::integer as modifier_concept_id
, null::integer as quantity
, null::integer as provider_id
, admissions.visit_occurrence_id
, null::integer as visit_detail_id -- the chartdate is never a time, when exist
, procedure_source_value
, gcpt_cpt4_to_concept.mimic_id as procedure_source_concept_id
, null::text as qualifier_source_value
FROM cpt_event
LEFT JOIN patients USING (subject_id)
LEFT JOIN admissions USING (hadm_id)
LEFT JOIN gcpt_cpt4_to_concept USING (procedure_source_value)
UNION ALL
SELECT
  procedure_occurrence_id
, patients.person_id
, coalesce(gcpt_procedure_to_concept.procedure_concept_id,0) as procedure_concept_id
, proc_event.procedure_datetime::date as procedure_date
, (proc_event.procedure_datetime) as procedure_datetime
, 38000275 as procedure_type_concept_id -- EHR order list entry
, null as modifier_concept_id
, null as quantity
, null as provider_id
, admissions.visit_occurrence_id
, null as visit_detail_id
, procedure_source_value
, procedure_source_concept_id -- from d_items mimic_id
, null as qualifier_source_value
FROM proc_event
LEFT JOIN patients USING (subject_id)
LEFT JOIN admissions USING (hadm_id)
LEFT JOIN gcpt_procedure_to_concept USING (itemid)
UNION ALL
SELECT
  procedure_occurrence_id
, patients.person_id
, coalesce(concept_proc_icd9.procedure_concept_id,0) as procedure_concept_id
, admissions.procedure_datetime::date as procedure_date
, (admissions.procedure_datetime) AS procedure_datetime
, 38003622 as procedure_type_concept_id
, null as modifier_concept_id
, null as quantity
, null as provider_id
, admissions.visit_occurrence_id
, null as visit_detail_id
, proc_icd.procedure_source_value
, coalesce(procedure_source_concept_id,0) as procedure_source_concept_id
, null as qualifier_source_value
FROM proc_icd
LEFT JOIN local_proc_icd USING (procedure_source_value)
LEFT JOIN patients USING (subject_id)
LEFT JOIN admissions USING (hadm_id)
LEFT JOIN concept_proc_icd9 USING (concept_code))
INSERT INTO omop.procedure_occurrence 
SELECT 
  procedure_occurrence_id
, person_id
, procedure_concept_id
, procedure_date
, procedure_datetime
, procedure_type_concept_id
, modifier_concept_id
, quantity
, provider_id
, visit_occurrence_id
, visit_detail_id
, procedure_source_value
, procedure_source_concept_id
, qualifier_source_value
FROM row_to_insert;

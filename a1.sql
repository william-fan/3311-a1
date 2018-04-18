-- COMP3311 18s1 Assignment 1
-- Written by William Fan (z5059967), April 2018

-- Q1: ...

create or replace view Q1(unswid, name)
as
    select People.unswid, People.name 
    from Course_enrolments 
    join People on People.id=Course_enrolments.student 
    group by People.unswid, People.name 
    having count(*)>65;
;

-- Q2: ...

create or replace view Q2(nstudents, nstaff, nboth)
as
    select * from 
        (select count(*) from Students where Students.id not in (select Staff.id from Staff)) as nstudents,
        (select count(*) from Staff where Staff.id not in (select Students.id from Students)) as nstaff,
        (select count(*) from Staff join Students on Staff.id=Students.id) as nboth;
;

-- Q3: ...

create or replace view Q3(name, ncourses)
as
    select People.name, count(*)
    from Course_staff 
    join Staff_roles on Course_staff.role=Staff_roles.id
    join People on Course_staff.staff=People.id
    where Staff_roles.name='Course Convenor' 
    group by People.name
    order by count(*) desc
    limit 1;
;

-- Q4: ...

create or replace view Q4a(id)
as
    select People.unswid
    from Program_enrolments 
    join Programs on Program_enrolments.program=Programs.id
    join People on Program_enrolments.student=People.id
    join Semesters on Program_enrolments.semester=Semesters.id
    where (Programs.code='3978' and Semesters.year='2005' and Semesters.term='S2');
;

create or replace view Q4b(id)
as
    select People.unswid
    from Stream_enrolments 
    join Program_enrolments on Stream_enrolments.partOf=Program_enrolments.id
    join People on Program_enrolments.student=People.id
    join Streams on Stream_enrolments.stream=Streams.id
    join Semesters on Program_enrolments.semester=Semesters.id
    where (Streams.code='SENGA1' and Semesters.year='2005' and Semesters.term='S2');
;

create or replace view Q4c(id)
as
    select People.unswid
    from Program_enrolments
    join Programs on Program_enrolments.program=Programs.id
    join OrgUnits on Programs.offeredBy=OrgUnits.id
    join Semesters on Program_enrolments.semester=Semesters.id
    join People on Program_enrolments.student=People.id
    where (OrgUnits.longname='School of Computer Science and Engineering' and Semesters.year='2005' and Semesters.term='S2');
;

-- Q5: ...

create or replace view Q5(name)
as
    select name from OrgUnits where id=(
        select facultyOf(OrgUnits.id)
        from OrgUnits
        join OrgUnit_types on OrgUnits.utype=OrgUnit_types.id
        where OrgUnit_types.name='Committee'
        and facultyOf(OrgUnits.id) is not null
        group by facultyOf(OrgUnits.id)
        order by count(*) desc
        limit 1
    );
;

-- Q6: ...

create or replace function Q6(integer) returns text
as
$$
    select name from People where id=$1 or unswid=$1;
$$ language sql
;

-- Q7: ...

create or replace function Q7(text)
	returns table (course text, year integer, term text, convenor text)
as $$
    select cast(Subjects.code as text), Semesters.year, cast(Semesters.term as text), People.name
    from Course_staff
    join Courses on Courses.id=Course_staff.course
    join Subjects on Subjects.id=Courses.subject
    join Staff_roles on Course_staff.role=Staff_roles.id
    join Semesters on Courses.semester=Semesters.id
    join People on Course_staff.staff=People.id
    where (Subjects.code=$1 and Staff_roles.name='Course Convenor');
$$ language sql
;

-- Q8: ...

create or replace function Q8(integer)
	returns setof NewTranscriptRecord
as $$
declare
    rec NewTranscriptRecord;
	UOCtotal integer := 0;
	UOCpassed integer := 0;
	wsum integer := 0;
	wam integer := 0;
	x integer;
begin
	select s.id into x
	from   Students s join People p on (s.id = p.id)
	where  p.unswid = $1;
	if (not found) then
		raise EXCEPTION 'Invalid student %',$1;
	end if;
	for rec in
		select su.code,
		         substr(t.year::text,3,2)||lower(t.term),
                 pr.code,
		         substr(su.name,1,20),
		         e.mark, e.grade, su.uoc
		from   People p
		         join Students s on (p.id = s.id)
                 join Course_enrolments e on (e.student = s.id)
		         join Courses c on (c.id = e.course)
		         join Subjects su on (c.subject = su.id)
		         join Semesters t on (c.semester = t.id)
                 join Program_enrolments pe on (pe.student=p.id and pe.semester=t.id)
                 join Programs pr on (pe.program=pr.id)
		where  p.unswid = $1
		order  by t.starting, su.code
	loop
		if (rec.grade = 'SY') then
			UOCpassed := UOCpassed + rec.uoc;
		elsif (rec.mark is not null) then
			if (rec.grade in ('PT','PC','PS','CR','DN','HD','A','B','C')) then
				-- only counts towards creditted UOC
				-- if they passed the course
				UOCpassed := UOCpassed + rec.uoc;
			end if;
			-- we count fails towards the WAM calculation
			UOCtotal := UOCtotal + rec.uoc;
			-- weighted sum based on mark and uoc for course
			wsum := wsum + (rec.mark * rec.uoc);
			-- don't give UOC if they failed
			if (rec.grade not in ('PT','PC','PS','CR','DN','HD','A','B','C')) then
				rec.uoc := 0;
			end if;

		end if;
		return next rec;
	end loop;
	if (UOCtotal = 0) then
		rec := (null,null,null,'No WAM available',null,null,null);
	else
		wam := wsum / UOCtotal;
		rec := (null,null,null,'Overall WAM',wam,null,UOCpassed);
	end if;
	-- append the last record containing the WAM
	return next rec;
end;
$$ language plpgsql
;


-- Q9: ...

create or replace function Q9(integer)
	returns setof AcObjRecord
as $$
declare
	rec AcObjRecord;
    x acad_object_groups;
    courseList text[];
    i text;
    j text;
    regex text;
begin
    --find pattern, check if its exists and is a pattern and not negated
    select * into x
    from acad_object_groups aog
    where $1 = aog.id;
    if (not found or x.gdefby != 'pattern' or x.negated) then
        return;
    end if;
    courseList := regexp_split_to_array(x.definition, E'\,');

    -- return empty if bad pattern, other than returning an exception
    foreach i in array courseList 
    loop
        if (i ~ '.*\/.*' or i ~ '.*\{.*') then
            return;
        end if;
    end loop;
        
    -- find courses that match pattern then add to table
    foreach i in array courseList 
    loop
        if (i ~ '^[A-Z]{4}[0-9]{4}$') then   -- return subject code
            rec := ('subject', i);
            return next rec;
        elsif (i ~ '^FREE.{4}|^GEN.{5}|^ZGEN.{4}') then   -- gen, free we ignore
            rec := ('subject', i);
            return next rec;
        elsif (i ~ '.*(#|\[|\|).*') then    -- search for pattern
            regex := replace(i, '#', '.');
            for rec in 
                select 'subject' as objtype, Subjects.code
                from Subjects 
                where Subjects.code ~ regex
                order by Subjects.code
            loop
                return next rec;
            end loop;
        end if;
    end loop;

end;
$$ language plpgsql
;


--set role percen_owner;
--set search_path=percen;

CREATE OR REPLACE FUNCTION personal_permisos_trg()
  RETURNS trigger AS
$BODY$
declare
  u_app       text;
  u_session   text;
  u_rol       text;
  u_puesto    text;
  u_des_geo   text;
  u_edita     boolean;
  niveles_geograficos text[]=array['provincia','comuna','fraccion','radio'];
  u_niv_geo   jsonb;
  u_dni       text;
  reg         record;
  oldPer      record;
  newPer      record;  
  v_column    text;
  ok_geo      boolean;
  pos_geo     integer;
  i_var       text;
  i_valor     jsonb;  
--Verificar el rol del usuario si es admin continúa sin problema
--Si el rol del usuario es coordinador tiene que comprobar que new.provincia y/o old.provincia (según corresponda)
--  sean iguales a la provincia de la persona del mismo DNI del usuario, lo mismo con comuna, fracción y radio. _Para facilita la iteración se puede usar to_jsonb(new) para poder iterar sobre la lista de campos
begin
    select split_part(nullif(setting,''),' ',1), session_user 
        into u_app, u_session
        from pg_settings where name='application_name';
        --por pgAdmin u_app=pgAdmin, por consola??
        --raise notice 'u_app %',u_app;
    --if u_app is not null then  --corregir condicion
        select rol, puesto, desagregacion_geografica, edita_personal, dni,jsonb_build_object('provincia', provincia, 'comuna',comuna, 'fraccion',fraccion,'radio',radio) 
            into u_rol, u_puesto, u_des_geo, u_edita, u_dni, u_niv_geo 
            from usuarios left join personal using(dni) left join puestos using(puesto)
            where usuario = u_app /*and tiene_usuario*/;
        --raise notice 'desGeo %, nivGeo %', u_des_geo, u_niv_geo::text;
        if TG_OP='DELETE' then
              reg=OLD;
              oldPer=OLD;
              newPer=OLD;
          elsIF TG_OP='UPDATE' then
              reg=NEW;
              oldPer=OLD;
              newPer=NEW;
          else
              reg=NEW;
              oldPer=NEW;
              newPer=NEW;
        end if;
        --raise notice 'newGeo %, oldGeo %', newPer::text, oldPer::text;
        case u_rol
          when 'admin' then
              return reg;
          when 'coordinador' then
              if not coalesce(u_edita,false) then
                  RAISE EXCEPTION 'Usuario inhabilitado para la edición de personal';
              elsIF u_des_geo is null then 
                  RAISE EXCEPTION 'El Usuario no tiene definido la desagregacion geografica';
                      --o puede editar todo?
              elsIF u_niv_geo->>u_des_geo is null then
                  RAISE EXCEPTION 'Usuario con desagregacion geografica % no indica valor en su registro de personal', u_des_geo;
              elsIF TG_OP='UPDATE' and u_dni= oldPer.dni and (newPer.puesto is distinct from oldPer.Puesto and oldPer.puesto is not null
                  or newPer.provincia is distinct from oldPer.provincia and oldPer.provincia is not null
                  or newPer.comuna is distinct from oldPer.comuna and oldPer.comuna is not null
                  or newPer.fraccion is distinct from oldPer.fraccion and oldPer.fraccion is not null) then
                  RAISE EXCEPTION 'Usuario conectado no puede modificar su campo rol ni campos geograficos con dato';
              else
                  pos_geo=array_position(niveles_geograficos,u_des_geo);
                  ok_geo=true;
                  for i in 1 .. pos_geo
                  loop 
                      i_var=niveles_geograficos[i];
                      i_valor=u_niv_geo->i_var;
                      ok_geo=ok_geo and i_valor = (to_jsonb(newPer)->i_var) and i_valor = (to_jsonb(oldPer)->i_var);
                      --raise notice 'var % valor% pervalnew % pervalold %', i_var, i_valor, new_geo->>i_var,old_geo->>i_var;
                      --raise notice 'var % valor % pervalnew % pervalold %', i_var, i_valor, to_jsonb(newPer)->>i_var,to_jsonb(oldPer)->>i_var;
                  end loop;
                  --raise notice 'posGeo %, okGeo %', pos_geo, ok_geo::text;
                  if ok_geo then
                      return reg;
                  else
                      RAISE EXCEPTION 'Solo puede editar registros de personal dentro de su jerarquia geografica';
                  end if;
              end if;
          else
              RAISE EXCEPTION 'Rol de Usuario sin tratamiento';
        end case;
    --else
        --???          
    --end if;
end;
$BODY$
LANGUAGE plpgsql ;

-- /*
drop trigger if exists personal_permisos_trg on personal;
CREATE TRIGGER personal_permisos_trg
  BEFORE INSERT OR UPDATE OR DELETE
  ON personal
  FOR EACH ROW
  EXECUTE PROCEDURE personal_permisos_trg();

-- */
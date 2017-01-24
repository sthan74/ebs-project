-- MOAC权限控制
begin
  mo_global.init('CUX');
end;

--查找销售人员
select * from jtf_rs_defresources_srp_v v
where v.name like '刘玉明%'

-- 按销售人员统计环年收入和成本匹配
select ctl.extended_amount,
       ooha.order_number,
       ctl.sales_order,
       hp.party_name,
       ct.trx_number,
       ct.trx_date,
       --ctl.interface_line_attribute6,
       --  oola.line_type_id,
       ottl.name,
       --  ooha.order_type_id,
       otth.name,
       oola.ordered_item,
       msib.description,
       oola.ordered_quantity,
       decode(ctl.quantity_invoiced,
              NULL,
              ctl.quantity_credited,
              ctl.quantity_invoiced) as invoiced_quantity,
       cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) as unit_cost,
       nvl(cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) *
           decode(ctl.quantity_invoiced,
                  NULL,
                  ctl.quantity_credited,
                  ctl.quantity_invoiced),
           0) as total_cost,
       ctl.extended_amount - nvl(cux_fin_pub.get_trx_line_cost(ctl.customer_trx_line_id) *
                                 decode(ctl.quantity_invoiced,
                                        NULL,
                                        ctl.quantity_credited,
                                        ctl.quantity_invoiced),
                                 0) as margin
  from ra_customer_trx_lines_all ctl
  join ra_customer_trx_all ct
    on ct.customer_trx_id = ctl.customer_trx_id
   and ct.primary_salesrep_id = '100005253' -- and ct.trx_number = '10000005011'
   and ct.trx_date between to_date('2016-01-01', 'yyyy-mm-dd') and
       to_date('2016-12-31', 'yyyy-mm-dd')
  join(oe_order_lines_all oola
  join oe_order_headers ooha
    on ooha.header_id = oola.header_id
  join oe_transaction_types otth
    on ooha.order_type_id = otth.transaction_type_id
  join oe_transaction_types ottl
    on oola.line_type_id = ottl.transaction_type_id --and ottl.transaction_type_id = 1254
 ) on oola.line_id = ctl.interface_line_attribute6
  join mtl_system_items_b msib
    on oola.ship_from_org_id = msib.organization_id
   and oola.inventory_item_id = msib.inventory_item_id
  join hz_cust_accounts hca
    on ct.bill_to_customer_id = hca.cust_account_id
  join hz_parties hp
    on hca.party_id = hp.party_id

--按客户统计环年销售（含税）和成本
select ra.bill_to_customer_id,
       hp.party_name,
       count(distinct ral.sales_order),
       sum(ral.extended_amount),,
       sum(cux_fin_pub.get_trx_line_cost(ral.customer_trx_line_id) *
           ral.quantity_invoiced)
/*rbs.name, ra.trx_number, ra.trx_date, ra.bill_to_customer_id, hp.party_name, ral.sales_order,
ral.interface_line_attribute6,  ral.extended_amount,
cux_fin_pub.get_trx_line_cost(ral.customer_trx_line_id)*ral.quantity_invoiced line_cost*/
  from ra_customer_trx_all ra
  join ra_customer_trx_lines_all ral
    on ra.customer_trx_id = ral.customer_trx_id
  join hz_cust_accounts hca
    on ra.bill_to_customer_id = hca.cust_account_id
  join hz_parties hp
    on hca.party_id = hp.party_id
  join ra_batch_sources_all rbs
    on rbs.batch_source_id = ra.batch_source_id
   and rbs.org_id = ra.org_id
   and rbs.name = 'OM 导入'
 where ra.org_id = '95' --北京组织
   and to_char(ra.trx_date, 'yyyy-mm') >= '2015-11' -- 环年
   and to_char(ra.trx_date, 'yyyy-mm') < '2016-11' -- 2015-11 到 2016-10
 group by ra.bill_to_customer_id, hp.party_name

-- 电商PO和SO关联对应关系：
 SELECT CPL.PO_ORDER_NUMBER, --电商平台采购订单编号
       POH.SEGMENT1,--采购订单编号
       OOH.ORDER_NUMBER,--ISO订单编号
       --OOH2.ORDER_NUMBER,--SO编号
       CPL.ITEM_NUMBER,--商品编号
       MSIT.DESCRIPTION,--商品名称
       --CPL.RECEIVE_OE_LINE_ID,--ISO行ID
       --CPL.OE_LINE_ID,--SO行ID
       --CPL.EBS_PO_LINE_ID,--PO行ID
       CPL.ORDER_QUANTITY,--数量
       CPL.UNIT_PRICE --含税单价
  FROM cux_ec_po_line_intf CPL,
       MTL_SYSTEM_ITEMS_B MSIT,
       PO_LINES_ALL POL,
       PO_HEADERS_ALL POH,
       OE_ORDER_LINES_ALL OOL,
       OE_ORDER_HEADERS_ALL OOH,
       OE_ORDER_LINES_ALL OOL2,
       OE_ORDER_HEADERS_ALL OOH2
 WHERE NVL(CPL.OE_LINE_ID, 0) <> 0
   AND NVL(CPL.RECEIVE_OE_LINE_ID, 0) <> 0
   AND CPL.EXECUTE_STAUTS='S'
   AND CPL.RECEIVE_ORG_ID=MSIT.ORGANIZATION_ID
   AND CPL.ITEM_NUMBER=MSIT.SEGMENT1
   AND CPL.EBS_PO_LINE_ID=POL.PO_LINE_ID
   AND POL.PO_HEADER_ID=POH.PO_HEADER_ID
   AND CPL.RECEIVE_OE_LINE_ID=OOL.LINE_ID
   AND OOL.HEADER_ID=OOH.HEADER_ID
   AND CPL.OE_LINE_ID=OOL2.LINE_ID
   AND OOL2.HEADER_ID=OOH2.HEADER_ID

-- 查询出库、PO保留、PO生成等有问题的电商调拨单
-- cux_hst_ec_po_oe_status_view 视图
create or replace view cux_hst_ec_po_oe_status_view as
select haou.name as buyer_org,
       pli.item_number,
       msib.description as item_desc,
       pha.segment1 as po_num,
       plla.quantity_received as po_rev_qty,
       oolaout.ordered_quantity as po_qty,
       pli.reservate_flag as po_rev_flag,
       oohaout.order_number as cust_ordnum,
       oolaout.attribute17 as ec_cust_num,
       oolaout.flow_status_code as cust_line_status,
       haou1.name as seller_org,
       oohain.order_number as seller_so,
       oolain.attribute17 as ec_seller_so,
       oolain.ordered_quantity as seller_ord_qty,
       oolain.shipped_quantity as seller_shp_qty,
       oolain.flow_status_code as seller_line_status,
       oohi.sheet_type as seller_so_type,
       pli.execute_stauts as po_itf_status,
       pli.execute_message as po_itf_message
  from cux_ec_po_line_intf pli
  join oe_order_lines_all oolaout
    on oolaout.line_id = pli.oe_line_id
   and oolaout.flow_status_code = 'AWAITING_SHIPPING'
  join oe_order_headers_all oohaout
    on oohaout.header_id = oolaout.header_id
  left join po_line_locations_all plla
    on pli.ebs_po_line_id = plla.po_line_id
  left join po_headers_all pha on pha.po_header_id = plla.po_header_id
  join mtl_system_items_b msib
    on msib.inventory_item_id = oolaout.inventory_item_id
   and msib.organization_id = oolaout.ship_from_org_id
  join oe_order_lines_all oolain
    on oolain.line_id = pli.receive_oe_line_id
  join oe_order_headers_all oohain
    on oolain.header_id = oohain.header_id
  join hr_all_organization_units haou
    on haou.organization_id = oolaout.ship_from_org_id
  join hr_all_organization_units haou1
    on haou1.organization_id = oolain.ship_from_org_id
  join cux_ec_oe_order_line_intf ooli
    on pli.receive_oe_line_id = ooli.ebs_order_line_id
  join cux_ec_oe_order_header_intf oohi
    on oohi.online_order_number = ooli.online_order_number

-- 按部门查询费用－－YUM 2016年统计
select a.*, b.description
  from (select gcc.segment3,
               --   gjl.period_name,
               sum(gjl.accounted_dr),
               sum(gjl.accounted_cr)
          from gl_je_lines gjl
          join gl_code_combinations gcc
            on gjl.code_combination_id = gcc.code_combination_id
           and gcc.segment2 = '1030201'
        -- and gcc.segment3 not like '2221%' --排除税科目
         where gjl.ledger_id = 2021 -- 内帐
           and gjl.period_name like '16%'
         group by gcc.segment3 --, gjl.period_name
        ) a
  join (Select a.flex_value, a.description, a.summary_flag
          From fnd_flex_values_vl a
         Where a.flex_value_set_id = 1015450) b
    on b.flex_value = a.segment3


-- 查询电商订单中已销账的发票，订单明细
select a.*
  from (select hou.name,
               hp.party_name,
               ta.trx_date,
               ta.trx_number,
               tl.sales_order,
               oola.attribute17,
               aps.amount_due_original,
               aps.amount_due_remaining,
               tl.description,
               tl.quantity_ordered,
               tl.quantity_credited,
               tl.quantity_invoiced,
               tl.extended_amount
          from ra_customer_trx_lines_all tl
          join oe_order_lines_all oola
            on oola.line_id = tl.interface_line_attribute6
           and oola.attribute17 is not null -- POS单号
        --and oola.ship_to_org_id = '48775' --and oola.ship_from_org_id = '129'
          join ar_payment_schedules_all aps
            on aps.customer_trx_id = tl.customer_trx_id
          join hr_all_organization_units hou
            on hou.organization_id = oola.ship_from_org_id
          join ra_customer_trx_all ta
            on ta.customer_trx_id = tl.customer_trx_id
          join hz_cust_accounts hca
            on ta.bill_to_customer_id = hca.cust_account_id
          join hz_parties hp
            on hca.party_id = hp.party_id
           and hp.party_name = 'POS通用客户'
         where tl.sales_order is not null -- 排除内部交易) a
 where a.amount_due_remaining = 0 -- 已销帐部分
    or (a.amount_due_remaining <> 0 and
       (a.amount_due_original - a.amount_due_remaining) > 0) -- 部分销账部分

-- 电商调拨对账报表
SELECT hou.name as 调入方,
       hou1.name as 调出方,
       --ool.attribute17 as 电商被调拨方单号,
       SUBSTR(ool.attribute17, 4, instr(ool.attribute17, '_') - 4) as 电商被调拨方单号,
       --ool2.attribute17 as 电商调拨方销售单号,
       SUBSTR(ool2.attribute17, 4, instr(ool2.attribute17, '_') - 4) as 电商调拨方销售单号,
       POH.SEGMENT1 as EBS采购订单编号,
       OOH.ORDER_NUMBER as 被调方EBS销售单号, --ISO订单编号
       OOH2.ORDER_NUMBER as 调入方EBS销售单号, --SO编号
       CPL.ITEM_NUMBER as 商品编号,
       MSIT.DESCRIPTION as 商品名称,
       --CPL.RECEIVE_OE_LINE_ID,--ISO行ID
       --CPL.OE_LINE_ID,--SO行ID
       --CPL.EBS_PO_LINE_ID,--PO行ID
       CPL.ORDER_QUANTITY as 订单数量,
       CPL.UNIT_PRICE as 含税单价,
       plla.quantity_received as 接收数量,
       plla.quantity_billed as 开票数量,
       (plla.quantity_received - plla.quantity_billed) * cpl.unit_price as 应付暂估金额,
       plla.quantity_billed * cpl.unit_price as 应付金额
  FROM cux_ec_po_line_intf CPL,
       MTL_SYSTEM_ITEMS_B MSIT,
       PO_LINES_ALL POL,
       PO_HEADERS_ALL POH,
       OE_ORDER_LINES_ALL OOL,
       OE_ORDER_HEADERS_ALL OOH,
       OE_ORDER_LINES_ALL OOL2,
       OE_ORDER_HEADERS_ALL OOH2,
       hr_all_organization_units hou,
       hr_all_organization_units hou1,
       (select p.po_line_id,
               sum(p.quantity_received) as quantity_received,
               sum(p.quantity_billed) as quantity_billed
          from po_line_locations_all p
          where p.quantity_received > 0
         group by p.po_line_id) Plla
 WHERE NVL(CPL.OE_LINE_ID, 0) <> 0
   AND NVL(CPL.RECEIVE_OE_LINE_ID, 0) <> 0
   AND CPL.EXECUTE_STAUTS = 'S'
   AND CPL.RECEIVE_ORG_ID = MSIT.ORGANIZATION_ID
   AND CPL.ITEM_NUMBER = MSIT.SEGMENT1
   AND CPL.EBS_PO_LINE_ID = POL.PO_LINE_ID
   AND POL.PO_HEADER_ID = POH.PO_HEADER_ID
   AND CPL.RECEIVE_OE_LINE_ID = OOL.LINE_ID
   AND OOL.HEADER_ID = OOH.HEADER_ID
   AND CPL.OE_LINE_ID = OOL2.LINE_ID
   AND OOL2.HEADER_ID = OOH2.HEADER_ID
   and poh.org_id = hou.organization_id
   and ooh.org_id = hou1.organization_id
   and plla.po_line_id = pol.po_line_id

--YUM AR - VAT 对账
select a.trx_date,
       a.party_name,
       a.vat_number,
       a.vat_status,
       a.vat_date,
       a.sales_order,
       a.trx_number,
       a.bill_to_site_use_id,
       a.location,
       a.cust_po_number,
       a.ordered_item,
       a.description,
       a.ordered_quantity,
       a.shipped_quantity,
       a.unit_price,
       a.amount_due_original,
       a.amount_due_remaining,
       a.vat_quantity,
       a.vat_amount,
       a.vat_up,
       a.vat_d_amount,
       a.vat_d_amount / a.unit_price as vat_d_qty,
       abs(a.vat_d_amount / a.unit_price) - nvl(a.shipped_quantity, 0) as diff_qty,
       (abs(a.vat_d_amount / a.unit_price) - nvl(a.shipped_quantity, 0)) *
       a.unit_price as diff_amount
  from (select --rctl.customer_trx_line_id,
        --rctl.customer_trx_id,
         to_char(rct.trx_date, 'yyyy-mm-dd') as trx_date,
         hp.party_name,
         hvh.vat_number,
         hvh.vat_status,
         hvh.vat_date,
         rctl.sales_order,
         rct.trx_number,
         rct.bill_to_customer_id as bill_to_customer_id,
         rct.bill_to_site_use_id as bill_to_site_use_id,
         uses.location,
         ooha.cust_po_number,
         oola.ordered_item,
         msib.description,
         oola.ordered_quantity,
         oola.shipped_quantity,
         oola.unit_selling_price  as unit_price,
         aps.amount_due_original,
         aps.amount_due_remaining,
         hvl.quantity             as vat_quantity,
         hvl.amount               as vat_amount,
         hvl.unit_price           as vat_up,
         hvdt.amount              as vat_d_amount
          from ra_customer_trx_lines_all rctl
          join hdsp.hdsp0003_vat_distributions_t hvdt
            on rctl.customer_trx_line_id = hvdt.trx_line_id
          join hdsp.hdsp0003_vat_lines_t hvl
            on hvdt.vat_line_id = hvl.vat_line_id
          join hdsp.hdsp0003_vat_headers_t hvh
            on hvh.vat_header_id = hvl.vat_header_id
           AND hvh.vat_status NOT IN ('CANCEL', 'DISCARD')
          join oe_order_lines_all oola
            on oola.line_id = rctl.interface_line_attribute6
          join ar_payment_schedules_all aps
            on aps.customer_trx_id = rctl.customer_trx_id
          -- and aps.amount_due_original - aps.amount_due_remaining >= 0
          -- and aps.amount_due_remaining <> 0
          join mtl_system_items_b msib
            on msib.inventory_item_id = oola.inventory_item_id
           and msib.organization_id = 113
          join oe_order_headers_all ooha
            on ooha.header_id = oola.header_id
          join ra_customer_trx_all rct
            on rct.customer_trx_id = rctl.customer_trx_id
          --  and to_char(rct.trx_date, 'yyyy-mm') = '2016-01'
          join hz_cust_accounts hca
            on hca.cust_account_id = rct.bill_to_customer_id
          join hz_parties hp
            on hp.party_id = hca.party_id
          join hz_cust_site_uses_all uses
          on rct.bill_to_site_use_id = uses.site_use_id
       -- join hz_cust_acct_sites_all sites
        --  on sites.cust_account_id = hca.cust_account_id
        -- and sites.org_id = rct.org_id
       --  and sites.cust_account_id = rct.bill_to_customer_id
      --  join hz_cust_site_uses_all uses
      --    on sites.cust_acct_site_id = uses.cust_acct_site_id
        -- and uses.org_id = sites.org_id
         and uses.site_use_code = 'BILL_TO'
         where rctl.org_id = 89 --and rct.trx_number = '10000009833'
        ) a

select a.*,
       a.vat_d_amount / a.unit_price as vat_d_qty,
       abs(a.vat_d_amount / a.unit_price) - nvl(a.shipped_quantity, 0) as diff_qty,
       (abs(a.vat_d_amount / a.unit_price) - nvl(a.shipped_quantity, 0)) *
       a.unit_price as diff_amount
  from (select --rctl.customer_trx_line_id,
        --rctl.customer_trx_id,
         to_char(rct.trx_date, 'yyyy-mm-dd'),
         hvh.vat_number,
         rctl.sales_order,
         ooha.cust_po_number,
         oola.ordered_item,
         msib.description,
         oola.ordered_quantity,
         oola.shipped_quantity,
         oola.unit_selling_price as unit_price,
         aps.amount_due_original,
         aps.amount_due_remaining,
         hvl.quantity as vat_quantity,
         hvl.amount as vat_amount,
         hvl.unit_price as vat_up,
         hvdt.amount as vat_d_amount
          from ra_customer_trx_lines_all rctl
          join hdsp0003_vat_distributions_t hvdt
            on rctl.customer_trx_line_id = hvdt.trx_line_id
          join hdsp0003_vat_lines_t hvl
            on hvdt.vat_line_id = hvl.vat_line_id
          join hdsp0003_vat_headers_t hvh
            on hvh.vat_header_id = hvl.vat_header_id
           AND hvh.vat_status NOT IN ('CANCEL', 'DISCARD')
          join oe_order_lines_all oola
            on oola.line_id = rctl.interface_line_attribute6
          join ar_payment_schedules_all aps
            on aps.customer_trx_id = rctl.customer_trx_id
        --   and aps.amount_due_original - aps.amount_due_remaining >= 0
        --   and aps.amount_due_remaining <> 0
          join mtl_system_items_b msib
            on msib.inventory_item_id = oola.inventory_item_id
           and msib.organization_id = 113
          join oe_order_headers_all ooha
            on ooha.header_id = oola.header_id
          join ra_customer_trx_all rct
            on rct.customer_trx_id = rctl.customer_trx_id
           and to_char(rct.trx_date, 'yyyy-mm-dd') >= '2016-01-01'
         where rctl.org_id = 89) a
select a.*, aps.amount_due_remaining, aps.amount_due_original from (SELECT cef.header_id,
       cef.order_number,
       cef.cust_po_number,
       cef.ordered_date,
       ceo.line_id,
       ceo.ordered_item,
       ceo.line_number,
       ceo.ordered_quantity,
       ceo.shipped_quantity,
       to_char(ceo.actual_shipment_date, 'yyyy-mm-dd')
  FROM oe_order_lines_all ceo, oe_order_headers_all CEF
 where CEO.Header_Id = CEF.Header_Id
   and cef.org_id = 89
   and cef.order_type_id <> 1117
   AND cef.order_number  IN
       (SELECT DISTINCT rctl.sales_order
          FROM apps.hdsp0003_vat_headers_t       hvht,
               apps.hdsp0003_vat_lines_t         hvlt,
               apps.hdsp0003_vat_distributions_t hvdt,
               apps.ra_customer_trx_all          rct,
               apps.ra_customer_trx_lines_all    rctl,
               apps.hz_cust_accounts             hca_bill,
               apps.hz_parties                   hp_bill,
               apps.hr_organization_units        hou,
               apps.oe_order_headers             ooh
         WHERE 1 = 1
           AND hvht.vat_header_id = hvlt.vat_header_id
           AND hvlt.vat_line_id = hvdt.vat_line_id
           AND rctl.customer_trx_line_id = hvdt.trx_line_id
           AND rctl.customer_trx_id = rct.customer_trx_id
           AND rct.org_id = 89 --hou.organization_id --84上海销售
              --AND rct.bill_to_customer_id = 1056 --1056上海总汇
              --AND rct.trx_number = '10000001454'
              /*   AND hou.name = 'OU_酒总集团'
              AND hp_bill.party_name = '内部客户_南翔厂'*/
           AND hvht.vat_status NOT IN ('CANCEL', 'DISCARD')
           AND rct.bill_to_customer_id = hca_bill.cust_account_id(+)
           AND hca_bill.party_id = hp_bill.party_id(+)
              -- AND hvht.vat_number = '52848881'
           AND ooh.order_number = rctl.sales_order)
   and ceo.line_id  in
       (SELECT DISTINCT rctl.interface_line_attribute6
          FROM apps.hdsp0003_vat_headers_t       hvht,
               apps.hdsp0003_vat_lines_t         hvlt,
               apps.hdsp0003_vat_distributions_t hvdt,
               apps.ra_customer_trx_all          rct,
               apps.ra_customer_trx_lines_all    rctl,
               apps.hz_cust_accounts             hca_bill,
               apps.hz_parties                   hp_bill,
               apps.hr_organization_units        hou,
               apps.oe_order_headers             ooh
         WHERE 1 = 1
           AND hvht.vat_header_id = hvlt.vat_header_id
           AND hvlt.vat_line_id = hvdt.vat_line_id
           AND rctl.customer_trx_line_id = hvdt.trx_line_id
           AND rctl.customer_trx_id = rct.customer_trx_id
           AND rct.org_id = 89 --hou.organization_id --84上海销售
              --AND rct.bill_to_customer_id = 1056 --1056上海总汇
              --AND rct.trx_number = '10000001454'
              /*   AND hou.name = 'OU_酒总集团'
              AND hp_bill.party_name = '内部客户_南翔厂'*/
           AND hvht.vat_status NOT IN ('CANCEL', 'DISCARD')
           AND rct.bill_to_customer_id = hca_bill.cust_account_id(+)
           AND hca_bill.party_id = hp_bill.party_id(+)
              -- AND hvht.vat_number = '52848881'
           AND ooh.order_number = rctl.sales_order)
   and to_char(ceo.actual_shipment_date, 'yyyy-mm-dd') > '2016-01-01') a
join ra_customer_trx_lines_all rct1 on a.line_id = rct1.interface_line_attribute6 and rct1.org_id = 89
--join ra_customer_trx_all rc1 on rc1. = rct1.customer_trx_id
join ar_payment_schedules_all aps on aps.customer_trx_id = rct1.customer_trx_id
and (aps.amount_due_original - aps.amount_due_remaining) = 0
